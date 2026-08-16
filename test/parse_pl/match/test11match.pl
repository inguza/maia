#!/usr/bin/env perl
#
# Copyright (c) 2025 Ola Lundqvist <ola@inguza.com>
#
use strict;
use warnings;
use JSON::PP;
use File::Basename;
use Getopt::Long;
use Cwd qw(getcwd);
use File::Temp qw(tempfile);
use File::Copy qw(copy);
use File::Find;

# lib/parse.pl — Parse assistant messages into change suggestions
# Usage: parse.pl [options] <command> [<raw-file-path> <workspace-root>
# Options:
# --loglevel LEVEL
# --session session_name
# --default-filenames-files file
# --allowed-extensions x,y,z
# Commands:
#  parse
#  process

# Implementation notes:
# - We use [ \t] for matching in a lot of places where the \t part is
#   most likely useless because we anyway expand tabs to spaces. It is
#   kept only because the danger of breaking working code. It is for example
#   still needed in all the $placeheld matching.
# - It is very important to consider multi-line matching. For example .* can
#   be very bad in many cases. Use precise matching if possible.
# - Tabs make things complicated but it looks like perl have some magic handling
#   for tab vs space mathing that solves this to a large extent. It still
#   needs some handling when checking space length in certain cases (test 6, 7).

# --- Logging helpers (from common.sh principles) ---
my %LOG_PRIORITIES = (
    DEBUG  => 0,
    EXTRA  => 1,
    INFO   => 2,
    NOTICE => 3,
    WARN   => 4,
    ERROR  => 5,
);
sub _should_log {
    my ($lvl) = @_;
    my $thr   = $ENV{TERM_LOGLEVEL} // 'NOTICE';
    my $lvl_n = $LOG_PRIORITIES{$lvl} // 0;
    my $thr_n = $LOG_PRIORITIES{$thr} // 0;
    return $lvl_n >= $thr_n;
}
sub debug     { _should_log('DEBUG')  and print STDERR "[DEBUG] @_\n" }
sub extra     { _should_log('EXTRA')  and print STDERR "[EXTRA] @_\n" }
sub info      { _should_log('INFO')   and print STDERR "[INFO] @_\n" }
sub notice    { _should_log('NOTICE') and print STDERR "[NOTICE] @_\n" }
sub warn_log  { _should_log('WARN')   and print STDERR "[WARN] @_\n" }
sub error_log { _should_log('ERROR')  and print STDERR "[ERROR] @_\n" }
sub die_log   { error_log(@_); exit 1 }
# -----------------------------------------------------

my $funcsigre = '\s*\w+\s*\(.*\)\s*\{';

# Parse options
my $loglevel;
my $session_name;
my $default_filenames_file;
my $tab_width = 8;
my $allowed_files;
my $whole = 0;
GetOptions(
    'loglevel|l=s' => \$loglevel,
    'whole+' => \$whole,
    'session=s'    => \$session_name,
    'default-filenames-file=s' => \$default_filenames_file,
    'tab-width=s'  => \$tab_width,
    'allowed-files=s' => \$allowed_files,
    ) or die_log "Invalid options\n";

my $allowed_files_regex = qr/\.(?:py|c|cpp|php|js|pl|pm|sh|txt)$/i; # default
if (defined $allowed_files) {
    if ("$allowed_files" eq "all") {
	$allowed_files_regex = qr/.*/;
    }
    else {
	$allowed_files_regex = qr/$allowed_files/;
    }
}

# Set TERM_LOGLEVEL (default NOTICE)
$ENV{TERM_LOGLEVEL} = $loglevel
    ? uc $loglevel
    : ($ENV{TERM_LOGLEVEL} // 'NOTICE');

# We expect first positional argument to be command: parse or process
my $cmd = shift @ARGV;

# Expect at least 2 positional args: <raw-file-path> and <workspace-root>
# plus optional default filenames after that
@ARGV >= 2 or die_log "Usage: $0 [--loglevel LEVEL] <raw-file-path> <workspace-root> [default-filename1 default-filename2 ...]";

# Raw file to parse
my $raw_file = shift @ARGV;

# Workspace root (mandatory)
my $ws_root = shift @ARGV;

# Derive idbase and change_dir
my ($filename, $change_dir) = fileparse($raw_file, qr/\.txt$/);
$change_dir =~ s/\/$//;
my $idbase;

# Validate change_dir exists
-d $change_dir
    or die_log "Change directory '$change_dir' does not exist";

# Read raw content
open my $fh, '<', $raw_file
    or die_log "Can't open '$raw_file': $!";
local $/;
my $raw = <$fh>;
close $fh;

my $NL = "\n";
$NL = "\r\n" if ($raw =~ /\r\n/);

# Default filenames to assign, unique per block needing one
my @default_filenames = read_default_filenames($default_filenames_file);

# Suggestion counter and the placeheld content
# These are "global" for a reason
my $n = 0;
my $placeheld = "";

if ("$cmd" eq "parse") {
    $idbase = $filename;
    &parse($raw, $filename);
}
elsif ("$cmd" eq "process") {
    $idbase = $filename;
    $idbase =~ s/-[a-z]+\.body$//;
    &process($raw);
}
else {
    die_log "Unknown command '$cmd'";
}

exit 0;
#############################################################
#################### Major functions ########################
#############################################################

######################## Parse ##############################
# Parses an already generated body and updates it
sub process {
    my ($body) = @_;
    # Extract $n from idbase suffix if possible (assumes idbase ends with -n or similar)
    # If idbase has a numeric suffix like "-0", "-1" etc, use that; else start at 1
    if ($idbase =~ /-(\d+)$/) {
        $n = $1;
        # Remove the numeric suffix from idbase for reuse
        $idbase =~ s/-\d+$//;
    }
    else {
        $n = 1;
    }
    
    my $lang = ""; # We could get this from meta, but then it must be there in the first place.
    # Read filename from metadata JSON if present
    my $meta_path = "$change_dir/${idbase}-$n-pending.json";
    my $fname = undef;
    if (-f $meta_path) {
	my $meta_json = read_json_file($meta_path);
	if (defined $meta_json->{filename} && length $meta_json->{filename}) {
	    $fname = $meta_json->{filename};
	}
	else {
	    notice "File name not defined for ${idbase}-$n.";
	}
    }
    else {
	warn_log "Can not open meta data file for ${idbase}-$n.";
    }
    process_snippet_or_file_block($lang, $body, $fname, \@default_filenames);
}

######################## Parse ##############################
# Parses a LLM response to create changes
sub parse {
    ($placeheld) = @_;
    $n = 1;
    #  .json: metadata for the entire change set
    my $root_meta = "$change_dir/$idbase-+-pending.json";
    {
	my %m = ( type => 'set' );
	if (defined $session_name && length $session_name) {
	    $m{session} = $session_name;
	}
	write_file($root_meta, JSON::PP->new->canonical->encode(\%m));
    }

    # We start with the --whole case.
    if ($whole > 0) {
	debug "Match type w1";
	my $body = $placeheld;
	$placeheld = "<<BLOCK #$n snippet>>\n";
	process_block(undef, $body, undef, \@default_filenames);
    }
    # Parsing loop with filename indication before fence:

    # JSON
    # Skip this for now until we actually have anything to test on. So far I have not seen it.
    #while ($placeheld =~ s/^.*?(```json[ \t]*\[.*?\][ \t]*```).*?\r\n?/<<BLOCK #$n+ json>>/ms) {
    #    my $block = $1;
    #    process_json_array($block);
    #    next;
    #}

    # File name in ** filename **
    # ## **filename** or
    # ## 1. **filename**
    # ```xxx
    # ...
    # ```
    # The ? after * and + are to ensure it is not greedy! This is important.
    while ($placeheld =~ s{
        ^
  	(	                       # (1) Heading to keep
          (?:\#+[ \t]*)                # heading marker (e.g. ##)
          (?:[0-9]+\.[0-9\.]*[ \t]*)?  # optional list marker
          (?:\#+[ \t]*)?               # optional second heading marker (e.g. ##)
	  \*\*[ \t]*([^\s]+)[ \t]*\*\* # (2) ** filename ** matched later
          [ \t]*\r?\n                  # header end
          (?:[ \t]*\r?\n)*?            # optional empty lines
          (?:[^\n]+\r?\n)*?            # optional instruction
          (?:[ \t]*\r?\n)*?            # optional empty lines
        )
        ^(```|''')([^\n]*)[ \t]*\r?\n  # (3) opening fence, (4) optional language
        (.*?)                          # (5) inner content
        ^\3[ \t]*?$                    # closing fence
        }{$1<<BLOCK #$n ($2)[t1]>>}msx) {
	my ($header, $fname, $fence, $lang, $body) = ($1, $2, $3, $4, $5);
	debug "Match type t1 '$fname, $lang'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # File name in ** filename **
    # 1. **filename** or
    # 1. ### **filename**
    # ```xxx
    # ...
    # ```
    # The ? after * and + are to ensure it is not greedy! This is important.
    while ($placeheld =~ s{
        ^
	(	                       # (1) Heading to keep
          (?:[0-9]+\.[0-9\.]*[ \t]*)   # list marker
          (?:[0-9]+\.[0-9\.]*[ \t]*)?  # optional second list marker
	  \*\*[ \t]*([^\s]+)[ \t]*\*\* # (2) ** filename ** matched later
          [ \t]*\r?\n                  # header end
          (?:[ \t]*\r?\r?\n)*?         # optional empty lines
          (?:[^\n]+\r?\n)*?            # optional instruction
          (?:[ \t]*\r?\n)*?            # optional empty lines
        )
        ^(```|''')([^\n]*)[ \t]*\r?\n  # (3) opening fence, (4) optional language
        (.*?)                          # (5) inner content
        ^\3[ \t]*?$                    # closing fence
        }{$1<<BLOCK #$n ($2)[t2]>>}msx) {
	my ($header, $fname, $fence, $lang, $body) = ($1, $2, $3, $4, $5);
	debug "Match type t2 '$fname, $lang'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # [filename: filename]
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ s{
        ^\[filename:[ \t\*]+([^\]]+?)[ \t\*]*\]\r?\n # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        (.*?)                            # (3) everything after
	^\2[ \t]*?$                      # matching closing fence
    	}{<<BLOCK #$n ($1)[f3]>>}msx) {
	my ($fname, $lang, $body) = ($1, $3, $4);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type f1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # [Updated filename]
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ s{
        ^\[Updated[ \t\*]+([^\]]+?)[ \t\*]*\]\r?\n # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        (.*?)                            # (3) everything after
	^\2[ \t]*?$                      # matching closing fence
    	}{<<BLOCK #$n ($1)[f2]>>}msx) {
	my ($fname, $lang, $body) = ($1, $3, $4);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type f1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # [filename]
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ s{
        ^\[[ \t\*]*([^\]]+?)[ \t\*]*\]\r?\n  # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        (.*?)                            # (3) everything after
	^\2[ \t]*?$                      # matching closing fence
    	}{<<BLOCK #$n ($1)[f1]>>}msx) {
	my ($fname, $lang, $body) = ($1, $3, $4);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type f1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # <optionaltext> `filename`:
    # ```
    # ...
    # ```
    while ($placeheld =~ s{
        ^
	(                         # (1) Instructions
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [^`]*?  		  # optional text
	  `([^`]+?)`:[ \t]*?\r?\n # (2) file name.
          (?:[ \t]*?\r?\n)?       # optional empty lines
	)
	^(```|''')([^\n]*?)\r?\n  # (3) opening fence and (4) optional language
        (.*?)                     # (5) everything after
	^\3[ \t]*?$               # matching closing fence
    	}{$1<<BLOCK #$n ($2)[u1]>>}msx) {
	my ($fname, $lang, $body) = ($2, $4, $5);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type u1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # Updated `filename`...
    # ```
    # ...
    # ```
    while ($placeheld =~ s{
        ^
	(                         # (1) Instructions
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [ \t]*Updated[ \t]+
	  `([^`]+?)`[^\n]*?\r?\n  # (2) file name. Very important to not have .* here because it matches multiple lines
          (?:[ \t]*?\r?\n)?       # optional empty lines
	)
	^(```|''')([^\n]*?)\r?\n  # (3) opening fence and (4) optional language
        (.*?)                     # (5) everything after
	^\3[ \t]*?$               # matching closing fence
    	}{$1<<BLOCK #$n ($2)[u1]>>}msx) {
	my ($fname, $lang, $body) = ($2, $4, $5);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type u1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # Here is the...`filename`...
    # ```
    # ...
    # ```
    while ($placeheld =~ s{
        ^
	(                         # (1) Instructions
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [ \t]*Here[ \t]+is[ \t]+the[ \t]+[^`]*?[ \t]*
	  `([^`]+?)`[^\n]*?\r?\n  # (2) file name. Very important to not have .* here because it matches multiple lines
          (?:[ \t]*?\r?\n)?       # optional empty lines
	)
	^(```|''')([^\n]*?)\r?\n  # (3) opening fence and (4) optional language
        (.*?)                     # (5) everything after
	^\3[ \t]*?$               # matching closing fence
    	}{$1<<BLOCK #$n ($2)[u1]>>}msx) {
	my ($fname, $lang, $body) = ($2, $4, $5);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type u1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
	next;
    }
    # Filename but no fence
    # [filename]
    # ...
    while ($placeheld =~ s{
        ^\[[ \t\*]*([^\]]+?)[ \t\*]*\][ \t]*?\r?\n  # “[filename]” on its own line
        (.*?)                       # non-greedy: everything after
        (?=^\[.+?\][ \t]*?\r?\n|\z) # until the next “[other]” header or end of text
    	}{<<BLOCK #$n ($1)[f2]>>}msx) {
	my ($fname, $body) = ($1, $2);
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type f2 '$fname'";
	process_block("", $body, $fname, \@default_filenames);
	next;
    }
    # <<BLOCK [filename]>>
    # ...
    # <<END_BLOCK>>
    while ($placeheld =~ s{
        <<BLOCK[ \t]*
	\[[ \t\*]*(.+?)[ \t\*]*\][ \t]* # (1) file name
	>>[ \t]*?\r?\n
        (.*?)    		    # (2) body
        (?=<<END_BLOCK>>|\z)        # lookahead for closer or end
    	}{<<BLOCK #$n: file ["$1"]>>}msx) {
	my ($fname, $body) = ($1, $2);
	debug "Match type b1 '$fname'";
	process_block("", $body, $fname, \@default_filenames);
	next;
    }
#    # Unified diff
#    while ($placeheld =~ s/^(diff --git.*?)(?=^diff --git|\z)/<<BLOCK #$n: patch>>/ms) {
#	my $body = $1;
#	my $rawb = "$change_dir/${idbase}-$n-pending.body";
#	write_file($rawb, $body);
#	process_diff($body);
#	next;
#    }
    # Generic fenced snippet (```...``` without a filename header)
    # We need to do this way, if we simply restrict to two liners, it will skip the
    # first fence and then treate the end fence as a start fence.
    my $thisheld = $placeheld;
    while ($thisheld =~ s{
       ^(```|''')([^\n]*)\r?\n  # (1) opening fence and (2) optional language
       (.*?)                    # (3) everything after
       ^\1[ \t]*?$	        # matching closing fence
       }{
       }msx) {
	my ($match, $lang, $body) = ($&, $2, $3);
	my $line_count = () = $body =~ /\r?\n/g;
	if ($line_count >= 2) {
	    # We only treat it as a full snippet if it contains at least two lines.
	    $placeheld =~ s/\Q$match\E/<<BLOCK #$n snippet>>/;
	    debug "Match type g1 '$lang'";
	    process_block($lang, $body, undef, \@default_filenames);
	}
    }
#    # Shell snippet
#    while ($placeheld =~ s/^(?:#!\/bin\/bash.*?\r?\n|(?:rm |mv |cp |patch |sed |awk ).*?)(?=\r?\n[ \t]*\r?\n|\z)/<<BLOCK #$n: shell>>/ms) {
#	my $body = $&;
#	my $rawb = "$change_dir/${idbase}-$n-pending.body";
#	write_file($rawb, $body);
#	process_shell($body);
#	next;
#    }
    $placeheld .= "$NL" unless $placeheld =~ /\n\z/;
    copy("$raw_file", "${raw_file}.orig")
	or do { warn_log "Copy failed to ${raw_file}.orig"; exit };
    open my $out, '>', $raw_file
	or die_log "Can't overwrite '$raw_file': $!";
    print $out $placeheld;
    close $out;
    info "Wrote placeholder version back to $raw_file";
}

exit 0;
###############################################################
################# Help Functions ##############################
###############################################################

sub read_json_file {
    my ($meta_path) = @_;
    open my $mf, '<', $meta_path or warn_log("Cannot open metadata file $meta_path: $!");
    local $/;
    my $meta_content = <$mf>;
    close $mf;
    my $meta_json = JSON::PP->new->decode($meta_content);
    return $meta_json;
}

sub read_default_filenames {
    my ($file) = @_;
    my @names = ();
    if (defined $file && -f $file) {
	open my $dfh, '<', $file or die_log "Can't open default filenames file: $!";
	my $file;
	while ($file = <$dfh>) {
	    $file =~ s/\r?\n//;
	    next if ($file =~ /^\s*$/);
	    $file =~ s/\s+$//;
	    $file =~ s/^\s+//;
	    push @names, $file;
	}
	close $dfh;
    }
    return @names;
}

sub write_default_filenames {
    my $file = shift @_;
    my @names = @_;
    if (defined $file) {
        open my $dfh, '>', $file or die_log "Can't update default filenames file: $!";
        print $dfh join("\n", @names), "\n";
        close $dfh;
    }
}

# Write files and log
sub write_file {
    my ($path, $content) = @_;
    open my $of, '>', $path
        or die_log "Can't write '$path': $!";
    print $of $content;
    close $of;
    info "Wrote file: $path";
}

# Write metadata JSON (now including patch filename)
sub write_meta {
    my ($idx, $fname, $lang) = @_;
    my $meta_path = "$change_dir/${idbase}-$idx-pending.json";

    my %m;
    if (-e $meta_path) {
        open my $jf, '<', $meta_path or die_log "Can't open '$meta_path': $!";
        local $/; my $txt = <$jf>; close $jf;
        %m = %{ JSON::PP->new->decode($txt) };
    }
    if (defined $session_name && length $session_name) {
	$m{session} = $session_name;
    }

    if (-e "$change_dir/${idbase}-$idx-pending.file") {
        $m{type}  = 'file';
    }
#    elsif (-e "$change_dir/${idbase}-$idx-pending.sh") {
#        $m{type}  = 'shell';
#    }
    elsif (-e "$change_dir/${idbase}-$idx-pending.snippet") {
	$m{type}  = 'snippet';
    }
    elsif (-e "$change_dir/${idbase}-$idx-pending.diff") {
        $m{type}  = 'diff';
    }
    elsif (-e "$change_dir/${idbase}-$idx-pending.txt") {
        $m{type}  = 'manual';
    }
    else {
	warn_log "Unknown type for '${idbase}-$idx'. Change data not saved.";
	return;
    }

    $m{filename} = $fname if defined $fname;
    $m{lang} = $lang if defined $lang;

    if (-e "$change_dir/${idbase}-$idx-pending.patch" && defined $fname && "$fname" ne "") {
        $m{type}  = 'patch';
    }

    my $json = JSON::PP->new->canonical->encode(\%m);
    write_file($meta_path, $json);
    if (! defined $fname) {
	notice "Change ${idbase}-$n created of type $m{type}";
    }
    else {
	notice "Change ${idbase}-$n created of type $m{type} for $fname";
    }
}

# Extracts the local filename by finding the longest common suffix of the two diff header filenames.
# Example input:
#   --- a/src/foo.c
#   +++ b/src/foo.c
# Returns: src/foo.c
# Handles undefined, empty, or "/dev/null" filenames gracefully.
sub extract_diff_local_filename {
    my ($file_minus, $file_plus) = @_;
    debug "x1 $file_minus, $file_plus";

    # Handle undefined, empty, or "/dev/null" cases early
    for ($file_minus, $file_plus) {
        $_ = '' unless defined $_;
    }

    # If one side is /dev/null or empty, use the other side
    if ($file_minus eq '' || $file_minus eq '/dev/null') {
        return $file_plus ne '' && $file_plus ne '/dev/null' ? $file_plus : '';
    }
    if ($file_plus eq '' || $file_plus eq '/dev/null') {
        return $file_minus ne '' && $file_minus ne '/dev/null' ? $file_minus : '';
    }

    # Split the paths into parts
    my @minus_parts = split m{/}, $file_minus;
    my @plus_parts  = split m{/}, $file_plus;

    my @common_parts = ();
    # Iterate from the end to find common suffix
    while (@minus_parts && @plus_parts) {
        last if $minus_parts[-1] ne $plus_parts[-1];
        unshift @common_parts, pop @minus_parts;
        pop @plus_parts;
    }

    # Join the common suffix parts back to a filename
    my $common_suffix = join("/", @common_parts);
    debug "x2 $common_suffix";

    # If no common suffix found, fallback to one of the filenames (prefer plus)
    return $common_suffix ne '' ? $common_suffix : ($file_plus ne '' ? $file_plus : $file_minus);
}

# Parses a unified diff content string, fixes common LLM diff issues (incorrect hunk header counts),
# and returns the fixed diff content string.
# Returns undef on failure.
sub fix_llm_diff_content {
    my ($diff_content) = @_;

    my @lines = split /\n/, $diff_content;
    my @fixed_lines;
    my $i = 0;
    my $n = scalar @lines;

    my $in_hunk = 0;
    my @hunk_lines;
    my ($old_start, $old_count, $new_start, $new_count);

    while ($i < $n) {
        my $line = $lines[$i];

        if ($line =~ /^@@\s*-(\d+),?(\d*)\s*\+(\d+),?(\d*)\s*@@/) {
            # If we were in a hunk, fix the previous hunk before starting a new one
            if ($in_hunk) {
                # Fix and flush previous hunk
                fix_and_flush_hunk_to_array(\@fixed_lines, $old_start, $old_count, $new_start, $new_count, \@hunk_lines);
                @hunk_lines = ();
            }

            $in_hunk = 1;
            $old_start  = $1;
            $old_count  = length($2) ? $2 : 1;
            $new_start  = $3;
            $new_count  = length($4) ? $4 : 1;

            # We will re-calculate counts below, so just store header for now
            push @fixed_lines, $line;
            $i++;
            next;
        }
        elsif ($in_hunk) {
            # Collect hunk lines until next hunk or end
            if ($line =~ /^@@/) {
                # New hunk - fix previous hunk first
                fix_and_flush_hunk_to_array(\@fixed_lines, $old_start, $old_count, $new_start, $new_count, \@hunk_lines);

                # Parse new hunk header
                $line =~ /^@@\s*-(\d+),?(\d*)\s*\+(\d+),?(\d*)\s*@@/ or do {
                    warn_log "Malformed hunk header: $line";
                    return undef;
                };
                $old_start  = $1;
                $old_count  = length($2) ? $2 : 1;
                $new_start  = $3;
                $new_count  = length($4) ? $4 : 1;
                @hunk_lines = ();
                push @fixed_lines, $line;
                $i++;
                next;
            }
            else {
                push @hunk_lines, $line;
                $i++;
                next;
            }
        }
        else {
            # Outside hunk, just copy line
            push @fixed_lines, $line;
            $i++;
        }
    }

    # If ended inside a hunk, fix and flush it
    if ($in_hunk) {
        fix_and_flush_hunk_to_array(\@fixed_lines, $old_start, $old_count, $new_start, $new_count, \@hunk_lines);
    }

    # Return fixed diff as string with newline endings
    return join("\n", @fixed_lines) . "\n";
}

# Helper to fix hunk header counts based on actual hunk lines, and append fixed hunk to fixed_lines array
sub fix_and_flush_hunk_to_array {
    my ($fixed_lines_ref, $old_start, $old_count, $new_start, $new_count, $hunk_lines_ref) = @_;

    # Count lines types in hunk
    my $old_lines = 0;
    my $new_lines = 0;

    for my $line (@$hunk_lines_ref) {
        if ($line =~ /^ /) {
            $old_lines++;
            $new_lines++;
        }
        elsif ($line =~ /^\-/) {
            $old_lines++;
        }
        elsif ($line =~ /^\+/) {
            $new_lines++;
        }
        else {
            # Unexpected line type; treat as context line to be safe
            $old_lines++;
            $new_lines++;
        }
    }

    # Fix counts if different
    my $old_count_fixed = $old_lines;
    my $new_count_fixed = $new_lines;

    # Replace last header line in fixed_lines with corrected counts
    my $header_line = pop @$fixed_lines_ref;
    #$header_line =~ s/^(@@ -)\d+,?\d*( \+)\d+,?\d*( @@)/$1$old_count_fixed$2$new_count_fixed$3/;
    #$header_line =~ s/^(@@ -)\d+,?\d*( \+)\d+,?\d*( @@)/$1$old_start,$old_count_fixed$2$new_start,$new_count_fixed$3/;
    $header_line =~ s/^(@@ -)(\d+),?\d*( \+)(\d+),?\d*( @@)/$1$2,$old_count_fixed$3$4,$new_count_fixed$5/;

    
    push @$fixed_lines_ref, $header_line;
    push @$fixed_lines_ref, @$hunk_lines_ref;
}

# Generates a patch file from the given diff content and filename.
# Adds the required --- and +++ headers and writes the patch file.
# Uses the global $ws_root to check if the file exists in the workspace.
sub generate_patch_from_diff {
    my ($filename, $diff_content, $patch_path) = @_;
    # Split instructions from hunks
    my ($instructions, $hunks) = ("", $diff_content);
    if ($diff_content =~ /\G(.*?)(^@@.*)/ms) {
        $instructions = $1;
        $hunks = $2;
    }
    my $old_file_line;
    if (-e "$ws_root/$filename") {
        $old_file_line = "--- a/$filename\n";
    } else {
        $old_file_line = "--- /dev/null\n";
    }
    my $new_file_line = "+++ b/$filename\n";
    # Compose patch content
    my $patch_content = $instructions . $old_file_line . $new_file_line . $hunks;
    write_file($patch_path, $patch_content);
    info "Generated patch file '$patch_path' from diff for '$filename'";
}

# Helper to generate a diff against workspace or /dev/null
#   make_patch($fname, $rawp, $patch_path)
# 
# - $fname       : relative repo filename (e.g. “foo.c”)
# - $rawp        : path to the generated file to diff against
# - $patch_path  : where to write the patch if non-empty
# 
# Returns the patch text (empty string if no diff or error).
sub make_patch {
    my ($fname, $rawp, $patch_path) = @_;
    # figure out which file in the repo we’re comparing, dev/null if the file is new
    my $src = -e "$ws_root/$fname" ? "$ws_root/$fname" : '/dev/null';
    my $slbl = -e "$ws_root/$fname" ? "a/$fname" : '/dev/null';
    my $cmd = qq{diff -u --label $slbl --label b/$fname "$src" "$rawp" 2>/dev/null};
    my $patch = `$cmd`;
    if ($patch) {
        write_file($patch_path, $patch);
    }
    return $patch;
}

sub expand_tabs {
    my ($text) = @_;
    # Replace tabs with $tab_width spaces
    $text =~ s/\t/' ' x $tab_width/eg;
    return $text;
}

sub get_indentation {
    my ($line) = @_;
    my ($indent) = ($line =~ /^(\s*)/);
    # Optionally normalize tabs to spaces here if needed
    return length($indent // '');
}

sub indentation_length {
    my ($str) = @_;
    $str = expand_tabs($str);
    return length($str);
}

sub can_splice_snippet {
    my ($body) = @_;
    my @lines = split /\r?\n/, $body;
    return 0 if @lines < 2;

    my $first_line = $lines[0];
    my $last_line  = $lines[-1];
    $first_line =~ /^([ \t]*)/;
    my $first_indent = $1;
    my $first_indent_len = indentation_length($first_indent);
    for my $i (1 .. $#lines - 1) {
	# Do not check empty lines
	next if ($lines[$i] =~ /^[ \t]*$/);
        my ($indent) = ($lines[$i] =~ /^([ \t]*)/);
	my $li = indentation_length($indent);
        return 0 if $li <= $first_indent_len;
    }
    return 1; # can splice
}

# tab expanded
sub indent_snippet {
    my ($body, $indent) = @_;
    my @lines = split /(\r?\n)/, $body;
    for my $line (@lines) {
	# Since we split by \r\n prefeving it every second line will have that
	# and they should not be indented.
	next if $line =~ /^\r?\n$/;
	next if ($line =~ /^[ \t]*$/); # Do not indent empty lines
	$line = "$indent$line";
    }
    return join("", @lines);
}

# Remove $first_indent spaces from start of every line (if present)
sub normalize_snippet_indentation {
    my ($body) = @_;
    my @lines = split /(\r?\n)/, $body;
    my $first_indent = get_indentation(expand_tabs($lines[0]));
    my $line;
    for $line (@lines) {
	# Since we split by \r\n prefeving it every second line will have that
	# and they should not be indented.
	next if $line =~ /^\r?\n$/;
	next if ($line =~ /^[ \t]*$/); # Skip empty lines
        if ($line =~ /^[ \t]{0,$first_indent}(.*)/) {
            $line = $1;
        }
    }
    return join("", @lines);
}

sub find_splice_target_file {
    # We assume tab expanded content
    my ($snippet_body, $file) = @_;
    my $search_root = "$ws_root";
    if (defined $file && $file ne "") {
	if (! -e "$ws_root/$file") {
	    debug "$file is a new file.";
	    return undef;
	}
	$search_root .= "/$file"; # We recurs through one file and it seems to work
    }
    my @lines = split /\r?\n/, $snippet_body;
    return undef if @lines < 2;
    my $first_line = $lines[0];
    $first_line =~ s/\r?\n$//;
    $first_line =~ s/\s+$//;
    my $last_line = $lines[-1];
    $last_line =~ s/\r?\n$//;
    $last_line =~ s/\s+$//;

    my $first_line_pattern = qr/^([ \t]*)\Q$first_line\E[ \t]*$/m;
    my @candidate_files = ();
    # Search files recursively in workspace root
    find(
        {
            wanted => sub {
                return unless -f $_;
                # Limit to source files if needed, e.g. *.c, *.php, *.sh etc.
                return if ($_ !~ $allowed_files_regex);
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                close $fh;
		debug "find start";
		if ($content =~ /$first_line_pattern/g) {
		    my $indent = $1;
		    my $indent_esc = quotemeta($indent);
		    debug "indent_esc='$indent_esc' '$indent'";
		    # TODO what we want here is a more precise match because now
		    # it allows any indentation between first and last line.
		    # What we want is some "confidence level" and then when the
		    # candidates are produced select the one with best confidence
		    # level. Also insead of a regexp like this we want a way where
		    # tabs can be expanded in a more relaxed form where it contributes
		    # to the confidence level instead.
		    # ^$indent_esc[ \t]+[^\n]+\r?\n # indented non-empty line
		    my $pattern = qr{
        (
	  ^$indent_esc			    # Indented part
	  \Q$first_line\E		    # First line
	  [ \t]*\r?\n			    # Space and new line
	  (?:
              ^[ \t]+[^\n]+\r?\n # indented non-empty line
              |		    		    # OR
              ^[ \t]*\r?\n                  # whitespace-only line
	  )+?
          ^$indent_esc\Q$last_line\E	    # indented last line
	  [ \t]*\r?\n?$			    # followed by space and optional new line
        )
    }msx;
		    if ($content =~ /$pattern/g) {
			debug "We have a match in ".$File::Find::name;
			push @candidate_files, {
			    path => $File::Find::name,
			    indent => $indent,
			    match_text => $&,
			};
		    }
		}
	    },
            no_chdir => 1,
        },
        $search_root
    );

    # Return undef if zero or multiple candidates found
    my $candidates = scalar @candidate_files;
    if ($candidates != 1) {
	debug "Found $candidates candidates for snippet, cannot splice.";
	return undef;
    }
    return $candidate_files[0];
}

#sub process_json_array {
#    my ($text) = @_;
#    my $data;
#    eval { $data = JSON::PP->new->decode($text) };
#    if ($@ || ref $data ne 'ARRAY') {
#        warn_log "Failed JSON parse: $@";
#        return;
#    }
#    foreach my $obj (@$data) {
#        my $fname   = $obj->{filename};
#        my $content = $obj->{content};
#	my $rawb = "$change_dir/${idbase}-$n-pending.body";
#	write_file($rawb, $content);
#        debug "JSON file: $fname";
#        my $rawp = "$change_dir/${idbase}-$n-pending.file";
#	write_file($rawp, $content);
#
#        make_patch($fname, $rawp, "$change_dir/${idbase}-$n-pending.patch");
#	write_meta($n, $fname);
#        $n++;
#    }
#}

sub process_file_block {
    my ($fname, $content) = @_;
    debug "block: $fname";
    my $rawp = "$change_dir/${idbase}-$n-pending.file";
    write_file($rawp, $content);
    make_patch($fname, $rawp, "$change_dir/${idbase}-$n-pending.patch");
    write_meta($n, $fname);
    $n++;
}

# Writes snippet file and metadata only.
sub process_snippet_block {
    my ($type, $block, $snip_path) = @_;
    debug "snippet $type";

    write_file($snip_path, $block);
    write_meta($n, undef, $type);
    $n++;
}

sub process_diff_block {
    my ($type, $block, $fname, $diff_path) = @_;
    debug "diff $type";

    # Correct mistakes by the LLM
    my $diff = fix_llm_diff_content($block);
    write_file($diff_path, $diff);
    # Generate patch file from diff content and filename
    if (defined $fname && $fname ne '') {
        my $patch_path = $diff_path;
        $patch_path =~ s/\.diff$/.patch/;
        generate_patch_from_diff($fname, $diff, $patch_path);
    } else {
        warn_log "No filename provided for diff block, patch file will not be generated";
    }
    write_meta($n, undef, $type);
    $n++;
}

sub process_block {
    my ($type, $block, $fname, $default_filenames_ref) = @_;
    my $pren = $n;
    my $content = $block;
    my $processed_any = 0;

    # We need to have two separate because regexps becase --- starts with - and that is the lookahead
    # in the second regexp and therefore that regexp cannot match --- separated diffs.
    # This is why we split this one in two separate regexps.
    # It is technically possible to combine the two but it is significantly more complicated.
    
    # Process multi-file diff chunks anchored by --- and +++ headers
    while ($content =~ s{
        \A
        (                                 # (1)
          (?:                             # optional instruction lines
	    (?!^---)                      # Stop at --- not allowed
	    (?!^@@)                       # Stop at @@ not allowed
	    ^[^\n]*\r?\n                  # instruction line
	  )*?               
	)
        ^---[ \t]+([^\t\r\n]+)            # --- filename (2) line capturing filename
        [^\r\n]*\r?\n                     # rest of --- line (e.g., timestamp)
        ^\+\+\+[ \t]+([^\t\r\n]+)         # +++ filename (3) line capturing filename
        [^\r\n]*\r?\n                     # rest of +++ line (e.g., timestamp)
	(                                 # (4)
          (?:                             # one or more hunks:
            ^@@[ \t]*-[\d,]+[ \t]*\+[\d,]+[ \t]*@@[^\r\n]*\r?\n # chunk header
            (?:
	      ^
	      (?!---)                     # Stop at ---
	      [ \-\+]                     # Start of line character allowed
	      [^\r\n]*\r?\n               # the rest of the line
            )+
          )+
        )
	(?=^---|\z)                       # <=== lookahead for next --- or end of string
    }{}msx) {
        my $diff_chunk = "$1$4";
	my $a1 = $1;
	my $a2 = $2;
	my $a3 = $3;
	my $a4 = $4;
        my $file_minus = $2;
        my $file_plus  = $3;
	my $body = $&;
        my $filename = extract_diff_local_filename($file_minus, $file_plus);
        debug "FILE DIFF x1 $filename '$a1' '$a2' '$a3' '$a4'";
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file($rawb, $body);
        process_diff_block('diff', $diff_chunk, $filename, "$change_dir/${idbase}-$n-pending.diff");
        $processed_any = 1;
    }
    # Process multi-file diff chunks anchored by --- and +++ headers and separated by "git lines"
    while ($content =~ s{
        \A
        (                                 # (1)
          (?:                             # optional instruction lines
	    (?!^---)                      # Stop at --- not allowed
	    (?!^@@)                       # Stop at @@ not allowed
	    ^[^\n]*\r?\n                  # instruction line
	  )*?               
	)
        ^---[ \t]+([^\t\r\n]+)            # --- filename (2) line capturing filename
        [^\r\n]*\r?\n                     # rest of --- line (e.g., timestamp)
        ^\+\+\+[ \t]+([^\t\r\n]+)         # +++ filename (3) line capturing filename
        [^\r\n]*\r?\n                     # rest of +++ line (e.g., timestamp)
	(                                 # (4)
          (?:                             # one or more hunks:
            ^@@[ \t]*-[\d,]+[ \t]*\+[\d,]+[ \t]*@@[^\r\n]*\r?\n # chunk header
            (?:
	      ^
	      (?!---)                     # Stop at ---
	      [ \-\+]                     # Start of line character allowed
	      [^\r\n]*\r?\n               # the rest of the line
            )+
          )+
        )
	(?=^[^ \-\+]|\z)                  # <=== lookahead for next non-chunk or end of string
    }{}msx) {
        my $diff_chunk = "$1$4";
	my $a1 = $1;
	my $a2 = $2;
	my $a3 = $3;
	my $a4 = $4;
        my $file_minus = $2;
        my $file_plus  = $3;
	my $body = $&;
        my $filename = extract_diff_local_filename($file_minus, $file_plus);
        debug "FILE DIFF x1 $filename '$a1' '$a2' '$a3' '$a4'";
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file($rawb, $body);
        process_diff_block('diff', $diff_chunk, $filename, "$change_dir/${idbase}-$n-pending.diff");
        $processed_any = 1;
    }
    # Process hunk-only diffs without file headers, if any content left
    while ($content =~ s{
        \A
        (
          (?:[^\n]*\r?\n)*?               # optional instruction lines
          (?:                             # one or more hunks:
            ^@@[ \t]*-[\d,]+[ \t]*\+[\d,]+[ \t]*@@[^\r\n]*\r?\n
            (?:^[ \-\+\\][^\r\n]*\r?\n)*  # hunk body lines
          )+
        )
    }{}msx) {
        my $hunk_chunk = $1;
	my $body = $&; # Same as $1 but we use this anyway in case we change something later
        debug "CHUNK DIFF (no filename)";
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file($rawb, $body);
        process_diff_block('diff', $hunk_chunk, $fname, "$change_dir/${idbase}-$n-pending.diff");
        $processed_any = 1;
    }

    # Any remaining content is treated as snippet or file block
    if ($content =~ /\S/) {
        debug "REST OF BLOCK as snippet/file";
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file($rawb, $content);
        process_snippet_or_file_block($type, $content, $fname, $default_filenames_ref);
        $processed_any = 1;
    }

    return unless $processed_any;

    # Replace original block placeholder with multiple block placeholders if needed
    if ($n > $pren + 1) {
        $placeheld =~ s/<<BLOCK #${pren}/<<BLOCK #${pren}-$n/;
    }
}

# Tries heuristic, then default filenames, else fallback to snippet.
sub process_snippet_or_file_block {
    my ($type, $block, $fname, $default_filenames_ref) = @_;

    # Add a list of patterns that always indicate a snippet, never a full file
    my @snippet_indicator_patterns = (
	qr/\.\.\.\s*existing code unchanged\s*\.\.\./i,
	qr/\.\.\.\s*existing methods unchanged\s*\.\.\./i,
	qr/\.\.\.\s*code omitted for brevity\s*\.\.\./i,
	qr/\.\.\.\s*unchanged code\s*\.\.\./i,
	qr/\.\.\.\s*rest of the code remains the same\s*\.\.\./i,
	qr/\.\.\.\s*code truncated\s*\.\.\./i,
	qr/\.\.\.\s*omitted for clarity\s*\.\.\./i,
	qr/\.\.\.\s*unchanged portion\s*\.\.\./i,
	qr/\.\.\.\s*other parts unchanged\s*\.\.\./i,
	qr/\.\.\.\s*code not shown\s*\.\.\./i,
	qr/\.\.\.\s*snippet continues\s*\.\.\./i,
	qr/\.\.\.\s*previous code unchanged\s*\.\.\./i,
	qr/\.\.\.\s*unchanged sections omitted\s*\.\.\./i,
	qr/\.\.\.\s*rest unchanged\s*\.\.\./i,
	qr/\.\.\.\s*code elided\s*\.\.\./i,
	qr/\.\.\.\s*intermediate code omitted\s*\.\.\./i,
	qr/\.\.\.\s*some code omitted\s*\.\.\./i,
    );

    # First check if block matches any snippet indicator pattern
    foreach my $pattern (@snippet_indicator_patterns) {
        if ($block =~ $pattern) {
            notice "Block matches snippet indicator pattern '$pattern'; treating as snippet";
            process_snippet_block($type, $block, "$change_dir/${idbase}-$n-pending.snippet");
            return;
        }
    }

    my $filename = "";
    if (can_splice_snippet($block)) {
	# First we check the indentation because we want to know if it helps to
	# search a second time
	my @tmplines = split /(\r?\n)/, $block;
	my $tmpfirst_indent = get_indentation($tmplines[0]);
	my $normalized_body = normalize_snippet_indentation($block);
	# Important to use the same body that is used when finding
	# if not the indentation of the block will be wrong.
	my $body = $block;
	my $fnamesearch = "";
	my $searchargprovided = 0;
	if (defined $fname && "$fname" ne "" && -e "$ws_root/$fname") {
	    $fnamesearch = $fname;
	}
	my $filenametop = $default_filenames_ref->[0];
	if ($fnamesearch eq "" && defined $filenametop && "$filenametop" ne "" && -e "$ws_root/$filenametop") {
	    $fnamesearch = $filenametop;
	}
	my $candidate = find_splice_target_file($body, $fname);
	if (! $candidate && $tmpfirst_indent > 0) {
	    my $candidate2 = find_splice_target_file($normalized_body, $fname);
	    if ($candidate2) {
		$body = $normalized_body;
		$candidate = $candidate2;
	    }
	}
	if ($candidate && $searchargprovided) {
	    shift @$default_filenames_ref;
	    info "Assigning default filename '$filename' to snippet #$n";
	    write_default_filenames($default_filenames_file, @$default_filenames_ref);
	}
	if ($candidate) {
            my $file_path  = $candidate->{path};
	    # The file indent is relative to the used body
            my $file_indent = $candidate->{indent};
            my $matched_block = $candidate->{match_text};
            notice "Splicing snippet into file: $file_path";
	    my $indented_body = indent_snippet($body, $file_indent);

            # Read original file content
            open my $fh, '<', $file_path or do {
                warn_log "Unable to open $file_path for splicing";
                return;
            };
            local $/;
            my $file_content = <$fh>;
            close $fh;

            # Replace matched block with indented snippet body
	    # TODO: It would be better if we instead of this simple
	    # replacement do some space comparisons and for the lines
	    # that are identical, check whether we can avoid changes
	    # to spacing.
            $file_content =~ s/\Q$matched_block\E/$indented_body/;

            # Write to pending file for patching
            my $out_path = "$change_dir/${idbase}-$n-pending.file";
            write_file($out_path, $file_content);

            # Generate patch
            my $relative_path = $file_path;
            $relative_path =~ s/^\Q$ws_root\E\/?//;
            make_patch($relative_path, $out_path, "$change_dir/${idbase}-$n-pending.patch");
            write_meta($n, $relative_path, $type);
            $n++;
            return;
        }
    }
    if ($fname) {
	process_file_block($fname, $block);
	return;
    }
    if (@$default_filenames_ref) {
	my $filename = shift @$default_filenames_ref;
	info "Assigning default filename '$filename' to file #$n";
	process_file_block($filename, $block);
	write_default_filenames($default_filenames_file, @$default_filenames_ref);
	return;
    }
    notice "No filename found or default filename left; emitting snippet #$n";
    process_snippet_block($type, $block, "$change_dir/${idbase}-$n-pending.snippet");
}

#sub process_diff {
#    my ($diff) = @_;
#    debug "Diff block";
#    my $diffp = "$change_dir/${idbase}-$n-pending.diff";
#    write_file($diffp, $diff);
#    my $ok = system(qq{cd "$ws_root" && patch --dry-run -p1 < "$diffp"}) == 0;
#    if ($ok) {
#        open my $in, '<', $diffp; local $/; my $d = <$in>; close $in;
#        my $patchp = "$change_dir/${idbase}-$n-pending.patch";
#        write_file($patchp, $d);
#    }
#    write_meta($n);
#    $n++;
#}

#sub process_shell {
#    my ($shell) = @_;
#    debug "Shell block";
#    my $sp = "$change_dir/${idbase}-$n-pending.sh";
#    write_file($sp, $shell);
#    write_meta($n);
#    $n++;
#}

sub process_manual {
    my ($txt) = @_;
    debug "Manual block";
    my $mp = "$change_dir/${idbase}-$n-pending.txt";
    write_file($mp, $txt);
    write_meta($n);
    $n++;
}
