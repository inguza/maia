#!/usr/bin/env perl
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
# Deprecated
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
# Use the common.pm in the same directory
use FindBin qw($Bin);
use lib $Bin;
use common;

# lib/parse.pl — Parse assistant messages into change suggestions
# Usage: parse.pl [options] <command> [<raw-file-path> <workspace-root>
# Options:
# --loglevel LEVEL
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

my $funcsigre = '\s*\w+\s*\(.*\)\s*\{';

# Parse options
my $loglevel;
my $default_filenames_file;
my $tab_width = 8;
my $allowed_files;
my $whole = 0;
my $auto_parse = 0;
GetOptions(
    'loglevel|l=s' => \$loglevel,
    'whole+' => \$whole,
    'default-filenames-file=s' => \$default_filenames_file,
    'tab-width=s'  => \$tab_width,
    'allowed-files=s' => \$allowed_files,
    'auto-parse!' => \$auto_parse,
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
@ARGV >= 2 or die_log "Usage: $0 process|parse [--loglevel LEVEL] [--auto-parse] <raw-file-path> <workspace-root> [default-filename1 default-filename2 ...]";

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

# New helper function to find correct fenced block substring among nested fences
# It is very importand that no text is modified. The only allowed thing is to remove text in
# the begining and end. If text is modified the parser will end up in an infinite loop.
sub find_fenced_block_among_nested {
    my ($text, $fence) = @_;
    my @lines = split /(\r?\n)/, $text;

    my $open_fence_count = 0;
    my $found_opening_fence = 0;

    my $full_block = '';
    my $body = '';

    # Regex to match opening fence line: fence string followed immediately by optional non-whitespace trailing text and optional spaces/tabs
    my $opening_fence_re = qr/^\Q$fence\E\S*[ \t]*$/;
    # Regex to match closing fence line: fence string followed only by spaces/tabs
    my $closing_fence_re = qr/^\Q$fence\E[ \t]*$/;

    while (@lines) {
        my $line_content = shift @lines // '';
        my $line_ending = shift @lines // '';

        if (!$found_opening_fence) {
            if ($line_content =~ $opening_fence_re) {
                $found_opening_fence = 1;
                $open_fence_count = 1;
            }
	    # Append all lines to full block unconditionally
	    $full_block .= $line_content . $line_ending;
        }
	else {
	    if ($line_content =~ $closing_fence_re) {
		$open_fence_count--;
		# Append all lines to full block unconditionall, but not the newline part because then it may
		# consume a little too much output.
		if ($open_fence_count == 0) {
		    $full_block .= $line_content;
		    last;
		}
	    }
	    elsif ($line_content =~ $opening_fence_re) {
		$open_fence_count++;
	    }
	    # Append all lines to full block unconditionally
	    $full_block .= $line_content . $line_ending;
	    
	    # Append all lines inside fenced block to body, including nested fences and closing fences (except the closing fence that ends the block)
	    $body .= $line_content . $line_ending;
	}
    }

    return ($full_block, $body);
}

######################## Parse ##############################
# Parses a LLM response to create changes
sub parse {
    ($placeheld) = @_;
    $n = 1;
    #  .json: metadata for the entire change set

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

    # *******************************************************************************************
    # IMPORTANT!
    # For all the fenced content matches we use greedy match .* to get to the last fence end this is then
    # corrected by find_fenced_block_among_nested. This is important to do for nested fences.
    #
    # Also it is very important to not use .* in multi-line regexps except for the case when a
    # catch multiple lines is wanted.
    #
    # LESS IMPORTANT
    # Closing fence is matched using ^\X[ \t]*?(?:\r?\n|\z) where X is a number
    # We could just as well have ^\X[ \t]*?$, but with the above we consume a \n as well that
    # reveals that it is important that find_fenced_block_among_nested stop at the fence and
    # do not have the extra newline. The reason is that if it produces an extra newline the
    # replacement is one newline too short because <<BLOCK...>> does not contain a newline.
    # And we should not have <<BLOCK ...>>\n as replacement because then \r\n may be converted to \n.
    # *******************************************************************************************

    # File name in ** filename **
    # ## **filename** or
    # ## 1. **filename**
    # ```xxx
    # ...
    # ```
    # The ? after * and + are to ensure it is not greedy! This is important.
    while ($placeheld =~ m{
        ^
  	(	                       # (1) Heading to keep
          (?:\#+[ \t]*)                # heading marker (e.g. ##)
          (?:[0-9]+\.[0-9\.]*[ \t]*)?  # optional list marker
          (?:\#+[ \t]*)?               # optional second heading marker (e.g. ##)
	  \*\*[ \t]*([^\s]+)[ \t]*\*\* # (2) ** filename ** matched later
          [ \t]*\r?\n                  # header end
	  ^[ \t]*(?:		       # optional instruction lines (not matching BLOCK)
	    (?!<<BLOCK)		       # not allowed to start with BLOCK
	    (?!\#+)                    # not allowed to start with heading marker
	    (?![ \t]*[0-9]+)           # not allowed to start with list marker
	    [^\n]*		       # any other line
            \r?\n		       # end of line
	  )*?
        )
        ^(```|''')([^\n]*)[ \t]*\r?\n  # (3) opening fence, (4) optional language
        .*                             # inner content, greedy match for nested fences
        ^\3[ \t]*?(?:\r?\n|\z)         # closing fence
        }msx) {
	my ($header, $fname, $fence, $lang, $full_match) = ($1, $2, $3, $4, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/$header<<BLOCK #$n ($fname)[t1]>>/;
	debug "Match type t1 '$fname, $lang'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # File name in ** filename **
    # 1. **filename** or
    # 1. ### **filename**
    # ```xxx
    # ...
    # ```
    # The ? after * and + are to ensure it is not greedy! This is important.
    while ($placeheld =~ m{
        ^
	(	                       # (1) Heading to keep
          (?:[0-9]+\.[0-9\.]*[ \t]*)   # list marker
          (?:[0-9]+\.[0-9\.]*[ \t]*)?  # optional second list marker
	  \*\*[ \t]*([^\s]+)[ \t]*\*\* # (2) ** filename ** matched later
          [ \t]*\r?\n                  # header end
	  ^[ \t]*(?:		       # optional instruction lines (not matching BLOCK)
	    (?!<<BLOCK)		       # not allowed to start with BLOCK
	    (?!\#+)                    # not allowed to start with heading marker
	    (?![ \t]*[0-9]+)           # not allowed to start with list marker
	    [^\n]*		       # any other line
            \r?\n		       # end of line
	  )*?
        )
        ^(```|''')([^\n]*)[ \t]*\r?\n  # (3) opening fence, (4) optional language
        .*                             # inner content, greedy match for nested fences
        ^\3[ \t]*?(?:\r?\n|\z)         # closing fence
        }msx) {
	my ($header, $fname, $fence, $lang, $full_match) = ($1, $2, $3, $4, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/$header<<BLOCK #$n ($fname)[t2]>>/;
	debug "Match type t2 '$fname, $lang'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # [filename: filename] case insensitive
    # [file: filename] case insensitive
    # [updated: filename] case insensitive
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ m{
        ^\[(?i:(?:filename|file|updated)):[ \t\*]+([^\]]+?)[ \t\*]*\][ \t]*\r?\n # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        .*                               # everything after, greedy match for nested fences
        ^\2[ \t]*?(?:\r?\n|\z)           # closing fence
    	}msx) {
	my ($fname, $fence, $lang, $full_match) = ($1, $2, $3, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/<<BLOCK #$n ($fname)[f3]>>/;
	debug "Match type f3 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # [filename filename] case insensitive
    # [file filename] case insensitive
    # [updated filename] case insensitive
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ m{
        ^\[(?i:(?:filename|file|updated))[ \t\*]+([^\]]+?)[ \t\*]*\][ \t]*\r?\n # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        .*                               # everything after, greedy match for nested fences
        ^\2[ \t]*?(?:\r?\n|\z)           # closing fence
    	}msx) {
	my ($fname, $fence, $lang, $full_match) = ($1, $2, $3, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/<<BLOCK #$n ($fname)[f2]>>/;
	debug "Match type f2 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # [filename]
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ m{
        ^\[[ \t\*]*([^\]]+?)[ \t\*]*\][ \t]*\r?\n  # (1) [filename]” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        .*                               # everything after, greedy match for nested fences
        ^\2[ \t]*?(?:\r?\n|\z)           # closing fence
    	}msx) {
	my ($fname, $fence, $lang, $full_match) = ($1, $2, $3, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/<<BLOCK #$n ($fname)[f1]>>/;
	debug "Match type f1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # [file] filename
    # ```xxx
    # ...
    # ```
    while ($placeheld =~ m{
        ^\[[ \t]*file[ \t]*\][ \t]*([^ ]+?)[ \t]*\r?\n  # (1) [file] filename” on its own line
        (?:[ \t]*\r?\n)?                 # optional empty lines
	^(```|''')([^\n]*?)\r?\n         # (2) opening fence and (2) optional language
        .*                               # everything after, greedy match for nested fences
        ^\2[ \t]*?(?:\r?\n|\z)           # closing fence
	}msx) {
	my ($fname, $fence, $lang, $full_match) = ($1, $2, $3, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/<<BLOCK #$n ($fname)[f1]>>/;
	debug "Match type f1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # <optionaltext> `filename`:
    # ```
    # ...
    # ```
    while ($placeheld =~ m{
        ^
	(                         # (1) Instructions to keep
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [^`]*?  		  # optional text
	  `([^`]+?)`:[ \t]*\r?\n  # (2) file name.
          (?:[ \t]*\r?\n)?        # optional empty lines
	)
	^(```|''')([^\n]*?)[ \t]*\r?\n # (3) opening fence and (4) optional language
        .*                        # everything after, greedy match for nested fences
        ^\3[ \t]*(?:\r?\n|\z)    # closing fence
    	}msx) {
	my ($header, $fname, $fence, $lang, $full_match) = ($1, $2, $3, $4, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/$header<<BLOCK #$n ($fname)[u1]>>/;
	debug "Match type u1 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # Updated `filename`...
    # ```
    # ...
    # ```
    while ($placeheld =~ m{
        ^
	(                         # (1) Instructions to keep
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [ \t]*Updated[ \t]+
	  `([^`]+?)`[^\n]*?\r?\n  # (2) file name
          (?:[ \t]*\r?\n)?       # optional empty lines
	)
	^(```|''')([^\n]*?)[ \t]*\r?\n # (3) opening fence and (4) optional language
        .*                        # everything after, greedy match for nested fences
        ^\3[ \t]*?(?:\r?\n|\z)    # closing fence
    	}msx) {
	my ($header, $fname, $fence, $lang, $full_match) = ($2, $3, $4, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	$placeheld =~ s/\Q$fenced_block\E/$header<<BLOCK #$n ($fname)[u2]>>/;
	debug "Match type u2 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # Here is the...`filename`...
    # ```
    # ...
    # ```
    while ($placeheld =~ m{
        ^
	(                         # (1) Instructions to keep
          (?:\#+[ \t]*)?          # optional heading marker (e.g. ##)
	  [ \t]*Here[ \t]+is[ \t]+the[ \t]+[^`]*?[ \t]*
	  `([^`]+?)`[^\n]*?\r?\n  # (2) file name
          (?:[ \t]*?\r?\n)?       # optional empty lines
	)
	^(```|''')([^\n]*?)\r?\n  # (3) opening fence and (4) optional language
        .*                        # everything after, greedy match for nested fences
        ^\3[ \t]*?(?:\r?\n|\z)    # closing fence
    	}msx) {
	my ($header, $fname, $fence, $lang, $full_match) = ($1, $2, $3, $4, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence, 1);
	$placeheld =~ s/\Q$fenced_block\E/$header<<BLOCK #$n ($fname)[u3]>>/;
	debug "Match type u3 '$fname'";
	process_block($lang, $body, $fname, \@default_filenames);
    }
    # Filename but no fence
    # [filename]
    # ...
    while ($placeheld =~ s{
        ^\[[ \t\*]*([^\]]+?)[ \t\*]*\][ \t]*\r?\n  # “[filename]” on its own line
        (.*?)                       # non-greedy: everything after
        (?=^\[.+?\][ \t]*\r?\n|\z) # until the next “[other]” header or end of text
    	}{<<BLOCK #$n ($1)[f2]>>}msx) {
	my ($fname, $body) = ($1, $2);
	# We may have premature file end and we should fix that
	$body .= "$NL" unless $body =~ /\n\z/;
	debug "Match type f2 '$fname'";
	process_block("", $body, $fname, \@default_filenames);
    }
    # <<BLOCK [filename]>>
    # ...
    # <<END_BLOCK>>
    while ($placeheld =~ s{
        <<BLOCK[ \t]*
	\[[ \t\*]*(.+?)[ \t\*]*\][ \t]* # (1) file name
	>>[ \t]*\r?\n
        (.*?)    		    # (2) body
        (?=<<END_BLOCK>>|\z)        # lookahead for closer or end
    	}{<<BLOCK #$n: file ["$1"]>>}msx) {
	my ($fname, $body) = ($1, $2);
	debug "Match type b1 '$fname'";
	process_block("", $body, $fname, \@default_filenames);
    }
    # Generic fenced snippet (```...``` without a filename header)
    # We need to do this way, if we simply restrict to two liners, it will skip the
    # first fence and then treate the end fence as a start fence.
    my $thisheld = $placeheld;
    while (!$auto_parse && $thisheld =~ m{
        ^(```|''')([^\n]*)[ \t]*\r?\n  # (1) opening fence and (2) optional language
        .*                       # everything after
        ^\1[ \t]*?(?:\r?\n|\z)    # closing fence
        }msx) {
	my ($fence, $lang, $full_match) = ($1, $2, $&);
	my ($fenced_block, $body) = find_fenced_block_among_nested($full_match, $fence);
	my $line_count = () = $body =~ /\r?\n/g;
	if ($line_count >= 2) {
	    # We only treat it as a full snippet if it contains at least two lines.
	    $placeheld =~ s/\Q$fenced_block\E/<<BLOCK #$n snippet>>/;
	    debug "Match type g1 '$lang'";
	    process_block($lang, $body, undef, \@default_filenames);
	}
	$thisheld =~ s/\Q$fenced_block\E//; # remove processed part
    }
#    # Shell snippet
#    while ($placeheld =~ s/^(?:#!\/bin\/bash.*?\r?\n|(?:rm |mv |cp |patch |sed |awk ).*?)(?=\r?\n[ \t]*\r?\n|\z)/<<BLOCK #$n: shell>>/ms) {
#	my $body = $&;
#	my $rawb = "$change_dir/${idbase}-$n-pending.body";
#	write_file_and_log($rawb, $body);
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

# Write file and log
sub write_file_and_log {
    my ($path, $content) = @_;
    &write_file($path, $content);
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
    write_file_and_log($meta_path, $json);
    if (! defined $fname) {
	notice "Change ${idbase}-$n created of type $m{type}";
    }
    else {
	notice "Change ${idbase}-$n created of type $m{type} for $fname";
    }
    # Now check if the root meta file exists, if not create it
    my $root_meta = "$change_dir/${idbase}-+-pending.json";
    if (! -e "$root_meta") {
	my %m = ( type => 'set' );
	write_file_and_log($root_meta, JSON::PP->new->canonical->encode(\%m));
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

# infer_start_lines_for_diff($diff_content, $original_content)
# For hunks with minimal headers (e.g. @@ @@), attempts to find the best matching location
# in the original content by matching context lines.
# Returns modified diff content with inferred start lines in hunk headers.
sub infer_start_lines_for_diff {
    my ($diff_content, $original_content) = @_;

    my @orig_lines = split /\r?\n/, $original_content;

    my @diff_lines = split /\n/, $diff_content;
    my @fixed_lines;

    my $i = 0;
    while ($i < @diff_lines) {
        my $line = $diff_lines[$i];
	if ($line =~ /^@@\s*(?:@@)?\s*$/) {
            # Minimal hunk header detected

            # Collect hunk lines until next hunk or end
            my @hunk_lines;
            $i++;
            while ($i < @diff_lines && $diff_lines[$i] !~ /^@@/) {
                push @hunk_lines, $diff_lines[$i];
                $i++;
            }

            # Extract context lines from hunk (lines starting with space)
            my @context_lines = grep { /^\s/ } @hunk_lines;
            my @context_text = map { substr($_,1) } @context_lines;

            # Search for best matching position in original file
            my $best_pos = find_best_match_position(\@orig_lines, \@context_text);

            # If no match found, default to line 1
            $best_pos = 1 unless defined $best_pos;

            # Count old and new lines in hunk
            my ($old_lines, $new_lines) = (0,0);
            for my $hl (@hunk_lines) {
                if ($hl =~ /^ /) {
                    $old_lines++;
                    $new_lines++;
                }
                elsif ($hl =~ /^\-/) {
                    $old_lines++;
                }
                elsif ($hl =~ /^\+/) {
                    $new_lines++;
                }
            }
            $old_lines = 1 if $old_lines == 0;
            $new_lines = 1 if $new_lines == 0;

            # Build new hunk header with inferred start lines and counts
            my $new_header = sprintf("@@ -%d,%d +%d,%d @@", $best_pos, $old_lines, $best_pos, $new_lines);
            push @fixed_lines, $new_header;
            push @fixed_lines, @hunk_lines;
            next;
        }
        else {
            push @fixed_lines, $line;
            $i++;
        }
    }

    return join("\n", @fixed_lines) . "\n";
}

# Helper function find_best_match_position(\@original_lines, \@context_lines)
# Finds the line number in original_lines where context_lines appear best (exact match).
# Returns line number (1-based) or undef if no match.
sub find_best_match_position {
    my ($orig_lines_ref, $context_lines_ref) = @_;
    my @orig = @$orig_lines_ref;
    my @context = @$context_lines_ref;

    return undef unless @context;

    # Try to find context lines as consecutive lines in original
    for my $i (0 .. $#orig - $#context) {
        my $matched = 1;
        for my $j (0 .. $#context) {
            if ($orig[$i + $j] ne $context[$j]) {
                $matched = 0;
                last;
            }
        }
        if ($matched) {
            return $i + 1; # line number is 1-based
        }
    }

    # If exact consecutive match not found, try approximate match: allow context lines to appear in order but with gaps
    # This is a simple heuristic: find first line matching context[0], then check following lines for others

    for my $i (0 .. $#orig) {
        next unless $orig[$i] eq $context[0];
        my $pos = $i + 1;
        my $k = 1;
        my $m = $pos;
        for my $l ($pos .. $#orig) {
            if ($k > $#context) { last; }
            if ($orig[$l] eq $context[$k]) {
                $k++;
            }
            $m = $l if $k > $#context;
        }
        if ($k > $#context) {
            return $pos;
        }
    }

    # No match found
    return undef;
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
    write_file_and_log($patch_path, $patch_content);
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
    my $e = $? >> 8;
    if ($e > 1) {
	warn "Could not generate the diff, error $e. The following command produced the error '$cmd'";
    }
    if ("patch" eq "") {
	notice "The parsed content is identical to the local content. Generating an empty patch file.";
	$patch .= "Identical content.\n\n";
	$patch .= "--- a/$fname\n";
	$patch .= "+++ a/$fname\n";
	$patch .= "@@ -1,0 +1,0 @@\n";
    }
    write_file_and_log($patch_path, $patch);
    return $patch;
}

# Quite complicated because the tab witdh depends on the position
sub expand_tabs {
    my ($text) = @_;
    my @lines = split /(\r?\n)/, $text;  # preserve line endings in split
    my $result = '';
    for (my $i = 0; $i < @lines; $i += 2) {
        my $line = $lines[$i];
        my $newline = $lines[$i + 1] // '';
        my $expanded_line = '';
        my $col = 0;
        foreach my $char (split //, $line) {
            if ($char eq "\t") {
                my $spaces = $tab_width - ($col % $tab_width);
                $expanded_line .= ' ' x $spaces;
                $col += $spaces;
            } else {
                $expanded_line .= $char;
                $col++;
            }
        }
        $result .= $expanded_line . $newline;
    }
    return $result;
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
    #$body = expand_tabs($body);
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

# tab expanded, with column awareness
sub indent_snippet {
    my ($body, $indent_str) = @_;

    # Calculate visual indent length of the matched block first line
    my $target_indent_len = length(expand_tabs($indent_str));

    my @lines = split /(\r?\n)/, $body;

    # Calculate visual indent length of snippet first line
    my ($snippet_first_line) = grep { $_ !~ /^\r?\n$/ } @lines; # first non-empty line text
    $snippet_first_line = '' unless defined $snippet_first_line;
    my ($snippet_indent_str) = ($snippet_first_line =~ /^([ \t]*)/);
    $snippet_indent_str = '' unless defined $snippet_indent_str;
    my $snippet_indent_len = length(expand_tabs($snippet_indent_str));

    my $indent_diff = $target_indent_len - $snippet_indent_len;

    # For each line, shift indentation by indent_diff visually, preserving original tabs/spaces
    for (my $i = 0; $i < @lines; $i += 2) {
        my $line = $lines[$i];
        my $newline = $lines[$i+1] // '';

        # Skip empty or whitespace-only lines
        if ($line =~ /^\s*$/) {
            $lines[$i] = $line;
            next;
        }

        # Extract original indentation string and rest of line
        my ($orig_indent, $rest) = $line =~ /^([ \t]*)(.*)$/;

        # Convert original indent to visual columns
        my $orig_indent_len = length(expand_tabs($orig_indent));

        # Calculate new indent length
        my $new_indent_len = $orig_indent_len + $indent_diff;
        $new_indent_len = 0 if $new_indent_len < 0;

        # Rebuild indentation preserving tabs as much as possible
        # We do this by keeping original tabs, and adding/removing spaces in front only

        # Count number of tabs in original indent and their visual width
        my $tab_width = 8; # or use global $tab_width if you prefer
        my $visual_pos = 0;
        my @chars = split //, $orig_indent;
        my $tabs_count = 0;
        my $spaces_count = 0;
        foreach my $c (@chars) {
            if ($c eq "\t") {
                $tabs_count++;
                $visual_pos += $tab_width - ($visual_pos % $tab_width);
            } else {
                $spaces_count++;
                $visual_pos++;
            }
        }

        # Calculate the visual width of tabs in original indent
        my $tabs_visual_width = $visual_pos - $spaces_count;

        # Calculate how many spaces to add or remove at start
        my $spaces_to_add = $new_indent_len - $orig_indent_len;

        # If spaces_to_add is positive, prepend spaces
        # If negative, remove spaces if possible (but do not remove tabs)
        my $new_indent = $orig_indent;
        if ($spaces_to_add > 0) {
            $new_indent = (' ' x $spaces_to_add) . $orig_indent;
        } elsif ($spaces_to_add < 0) {
            # Remove spaces from start of original indent if possible
            my $spaces_to_remove = -$spaces_to_add;
            if ($orig_indent =~ /^([ \t]*)(.*)$/) {
                my $leading_ws = $1;
                my $rest_ws = $2;
                # Remove spaces from leading_ws up to spaces_to_remove
                my $removed = 0;
                my @chars = split //, $leading_ws;
                my @new_chars;
                foreach my $c (@chars) {
                    if ($c eq ' ' && $removed < $spaces_to_remove) {
                        $removed++;
                        next;
                    }
                    push @new_chars, $c;
                }
                $new_indent = join('', @new_chars) . $rest_ws;
            }
        }

        # Replace line indentation with new_indent, keep rest of line
        $lines[$i] = $new_indent . $rest;
    }

    return join('', @lines);
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

sub preprocess_snippet {
    my ($snippet, $lang, $filename) = @_;

    my $ext;
    if (defined $filename && $filename =~ /\.([^.]+)$/) {
        $ext = lc $1;
    }

    # Split snippet into lines, capturing line endings separately
    my @lines = split /(\r?\n)/, $snippet;

    my @filtered_lines;
    for (my $i = 0; $i < @lines; $i += 2) {
        my $line_content = $lines[$i];
        my $line_ending = $lines[$i+1] // '';

        # Skip lines that are comment or blank, now passing lang and ext
        if (!is_comment_or_blank_line($line_content, $lang, $ext)) {
            push @filtered_lines, $line_content . $line_ending;
        }
    }

    return join('', @filtered_lines);
}

sub is_comment_or_blank_line {
    my ($line, $lang, $ext) = @_;

    return 1 if $line =~ /^\s*$/; # blank line

    my %lang_comment_patterns = (
	'bash' => qr/^\s*#/,
	'sh'   => qr/^\s*#/,
	'shell'=> qr/^\s*#/,
	'perl' => qr/^\s*#/,
	'python' => qr/^\s*#/,
	'ruby' => qr/^\s*#/,
	'php'  => qr/^\s*\/\//,
	'js'   => qr/^\s*\/\//,
	'javascript' => qr/^\s*\/\//,
	'c'    => qr/^\s*\/\//,
	'cpp'  => qr/^\s*\/\//,
	'java' => qr/^\s*\/\//,
	# ... add more as needed
	);

    my %ext_comment_patterns = (
	'sh'   => qr/^\s*#/,
	'bash' => qr/^\s*#/,
	'pl'   => qr/^\s*#/,
	'py'   => qr/^\s*#/,
	'rb'   => qr/^\s*#/,
	'php'  => qr/^\s*\/\//,
	'js'   => qr/^\s*\/\//,
	'c'    => qr/^\s*\/\//,
	'cpp'  => qr/^\s*\/\//,
	'java' => qr/^\s*\/\//,
	# markdown and text have no comment pattern
	'md'   => qr/^$/,
	'txt'  => qr/^$/,
	);

    my $pattern;

    # Prefer language tag comment pattern if present
    if (defined $lang && exists $lang_comment_patterns{lc $lang}) {
	$pattern = $lang_comment_patterns{lc $lang};
    }
    # Else try extension
    elsif (defined $ext && exists $ext_comment_patterns{lc $ext}) {
	$pattern = $ext_comment_patterns{lc $ext};
    }
    else {
	# fallback (e.g. assume markdown/plain text with no comment lines)
	$pattern = qr/^$/;
    }

    return $line =~ $pattern;
}

sub find_splice_target_file {
    my ($snippet_body, $file, $lang) = @_;
    my $search_root = "$ws_root";
    if (defined $file && $file ne "") {
	if (! -e "$ws_root/$file") {
	    debug "$file is a new file.";
	    return undef;
	}
        $search_root .= "/$file"; # We recurse through one file and it seems to work
    }
    # Prepare normalized snippet lines (tabs expanded)
    my $normalized_snippet_body = expand_tabs($snippet_body);
    # Pass lang and file to preprocess_snippet
    my $processed_snippet = preprocess_snippet($normalized_snippet_body, $lang, $file);
    my @snippet_lines = split /\r?\n/, $processed_snippet;
    return undef if @snippet_lines < 2;
    my $snippet_first_line = $snippet_lines[0];
    my $snippet_last_line = $snippet_lines[-1];

    # Compute indentation lengths for snippet first and last lines
    my $snippet_first_indent_len = indentation_length(($snippet_first_line =~ /^(\s*)/)[0] // '');
    my $snippet_last_indent_len  = indentation_length(($snippet_last_line =~ /^(\s*)/)[0] // '');

    # Compute relative indentation of last line to first line in snippet
    my $snippet_last_rel_indent = $snippet_last_indent_len - $snippet_first_indent_len;

    my @candidate_files;

    # Search files recursively in workspace root
    find(
        {
            wanted => sub {
                return unless -f $_;
                return if ($_ !~ $allowed_files_regex);
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                close $fh;

                my @original_lines = split /\r?\n/, $content;
                my $normalized_content = expand_tabs($content);
                my @norm_lines = split /\r?\n/, $normalized_content;

                for my $i (0 .. $#norm_lines) {
                    my $candidate_first_line = $norm_lines[$i];
                    my $candidate_first_line_trim = $candidate_first_line;
                    $candidate_first_line_trim =~ s/^\s*//;
                    my $snippet_first_line_trim = $snippet_first_line;
                    $snippet_first_line_trim =~ s/^\s*//;

                    next unless $candidate_first_line_trim eq $snippet_first_line_trim;

                    # Search for candidate last lines matching snippet last line and relative indentation
                    for my $j ($i .. $#norm_lines) {
                        my $candidate_last_line = $norm_lines[$j];
                        my $candidate_last_line_trim = $candidate_last_line;
                        $candidate_last_line_trim =~ s/^\s*//;
                        my $snippet_last_line_trim = $snippet_last_line;
                        $snippet_last_line_trim =~ s/^\s*//;

                        next unless $candidate_last_line_trim eq $snippet_last_line_trim;

                        # Compute indentation lengths for candidate first and last lines
                        my $candidate_first_indent_len = indentation_length(($candidate_first_line =~ /^(\s*)/)[0] // '');
                        my $candidate_last_indent_len  = indentation_length(($candidate_last_line =~ /^(\s*)/)[0] // '');

                        # Compute relative indentation of last line to first line in candidate
                        my $candidate_last_rel_indent = $candidate_last_indent_len - $candidate_first_indent_len;

                        next unless $candidate_last_rel_indent == $snippet_last_rel_indent;

                        # Check intermediate lines indentation: must be strictly greater than candidate first line indent
                        my $all_indent_ok = 1;
                        for my $k ($i + 1 .. $j - 1) {
                            my $cand_line = $norm_lines[$k];
			    # Skip empty or whitespace-only lines
                            next if is_comment_or_blank_line($cand_line, $lang, $_);
                            my $cand_indent_len = indentation_length(($cand_line =~ /^(\s*)/)[0] // '');
                            if ($cand_indent_len <= $candidate_first_indent_len) {
                                $all_indent_ok = 0;
                                last;
                            }
                        }
                        next unless $all_indent_ok;

                        # Extract original matched lines from original content
                        my $start = $i;
                        my $end = $j;
                        $start = 0 if $start < 0;
                        $end = $#original_lines if $end > $#original_lines;

                        my $matched_block = join("\n", @original_lines[$start .. $end]);
                        $matched_block .= "\n" if $content =~ /\n$/;

                        # Extract indentation string from original matched first line (with tabs preserved)
                        my ($indent_str) = ($original_lines[$start] =~ /^(\s*)/);

                        debug "Relative indent match found in ".$File::Find::name." at lines ".($start+1)."-".($end+1);

			push @candidate_files, {
			    path => $File::Find::name,
                            indent => $indent_str,
                            match_text => $matched_block,
			};
		    }
		}
	    },
            no_chdir => 1,
        },
        $search_root
    );

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
#	write_file_and_log($rawb, $content);
#        debug "JSON file: $fname";
#        my $rawp = "$change_dir/${idbase}-$n-pending.file";
#	write_file_and_log($rawp, $content);
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
    write_file_and_log($rawp, $content);
    make_patch($fname, $rawp, "$change_dir/${idbase}-$n-pending.patch");
    write_meta($n, $fname);
    $n++;
}

# Writes snippet file and metadata only.
sub process_snippet_block {
    my ($type, $block, $snip_path) = @_;
    debug "snippet $type";

    write_file_and_log($snip_path, $block);
    write_meta($n, undef, $type);
    $n++;
}

sub process_diff_block {
    my ($type, $rawblock, $fname, $diff_path) = @_;
    debug "diff $type";

    my $block = $rawblock;

    # Correct the simplified format produced by some LLM to have proper start lines
    if ($block =~ /^@@\s*(?:@@)?\s*$/m) {
	if (defined $fname && $fname ne '') {
	    my $orig_file = "$ws_root/$fname";
	    if (-f $orig_file) {
		open my $ofh, '<', $orig_file or warn_log("Cannot open original file $orig_file for start line inference");
		local $/;
		my $orig_content = <$ofh>;
		close $ofh;
		$block = infer_start_lines_for_diff($rawblock, $orig_content);
	    }
	}
    }

    # Correct mistakes by the LLM
    my $diff = fix_llm_diff_content($block);

    write_file_and_log($diff_path, $diff);
    # Generate patch file from diff content and filename
    if (defined $fname && $fname ne '') {
        my $patch_path = $diff_path;
        $patch_path =~ s/\.diff$/.patch/;
        generate_patch_from_diff($fname, $diff, $patch_path);
	info "Generated patch file '$patch_path' from diff for '$fname'";
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
        write_file_and_log($rawb, $body);
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
        my $file_minus = $2;
        my $file_plus  = $3;
	my $body = $&;
        my $filename = extract_diff_local_filename($file_minus, $file_plus);
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file_and_log($rawb, $body);
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
        write_file_and_log($rawb, $body);
        process_diff_block('diff', $hunk_chunk, $fname, "$change_dir/${idbase}-$n-pending.diff");
        $processed_any = 1;
    }

    # Any remaining content is treated as snippet or file block
    if ($content =~ /\S/) {
        debug "REST OF BLOCK as snippet/file";
        my $rawb = "$change_dir/${idbase}-$n-pending.body";
        write_file_and_log($rawb, $content);
        process_snippet_or_file_block($type, $content, $fname, $default_filenames_ref);
        $processed_any = 1;
    }

    return unless $processed_any;

    # Replace original block placeholder with multiple block placeholders if needed
    if ($n > $pren + 1) {
        $placeheld =~ s/<<BLOCK #${pren}/<<BLOCK #${pren}-$n/;
    }
}

# Splice snippet into matched block with tab-aware diff to avoid changes caused solely by tabs vs spaces.
# Returns the replacement string to substitute in the file.
sub splice_snippet_with_tab_awareness {
    my ($matched_block, $snippet_body) = @_;

    # Split into lines preserving line endings
    my @matched_lines = split /(\r?\n)/, $matched_block;
    my @snippet_lines = split /(\r?\n)/, $snippet_body;

    # Extract only text lines (lines are every even index, line endings are odd indices)
    my @matched_text_lines = map { $matched_lines[$_] } grep { $_ % 2 == 0 } 0..$#matched_lines;
    my @matched_line_ends  = map { $matched_lines[$_] } grep { $_ % 2 == 1 } 0..$#matched_lines;

    my @snippet_text_lines = map { $snippet_lines[$_] } grep { $_ % 2 == 0 } 0..$#snippet_lines;
    my @snippet_line_ends  = map { $snippet_lines[$_] } grep { $_ % 2 == 1 } 0..$#snippet_lines;

    # Expand tabs to spaces for comparison only
    my @matched_expanded = map { expand_tabs($_) } @matched_text_lines;
    my @snippet_expanded = map { expand_tabs($_) } @snippet_text_lines;

    # Use a simple diff algorithm to align lines and identify changed lines
    # We implement a basic Longest Common Subsequence (LCS) line diff

    my ($actions) = diff_lines(\@matched_expanded, \@snippet_expanded);

    # $actions is an arrayref of hashrefs with keys:
    # - type: 'equal', 'replace', 'insert', 'delete'
    # - matched_idx: index in matched block lines (undef for insert)
    # - snippet_idx: index in snippet lines (undef for delete)

    my @result_lines;

    for my $act (@$actions) {
        if ($act->{type} eq 'equal') {
            # Lines equal ignoring tabs/spaces, preserve original matched block line with original line ending
            my $idx = $act->{matched_idx};
            push @result_lines, $matched_text_lines[$idx];
            push @result_lines, ($matched_line_ends[$idx] // "\n");
        }
        elsif ($act->{type} eq 'replace') {
            # Replace one matched line with one snippet line
            # Replace matched line with snippet line (original tabs/spaces preserved)
            my $sidx = $act->{snippet_idx};
            push @result_lines, $snippet_text_lines[$sidx];
            push @result_lines, ($snippet_line_ends[$sidx] // "\n");
        }
        elsif ($act->{type} eq 'insert') {
            # Insert snippet line(s)
            my $sidx = $act->{snippet_idx};
            push @result_lines, $snippet_text_lines[$sidx];
            push @result_lines, ($snippet_line_ends[$sidx] // "\n");
        }
        elsif ($act->{type} eq 'delete') {
            # Delete matched line: skip adding anything
            # i.e. omit this line from output
        }
    }

    return join('', @result_lines);
}

# Simple line diff implementing Longest Common Subsequence (LCS) for arrays of strings
# Returns an arrayref of actions describing how to convert @old_lines to @new_lines
# Each action is a hashref with keys:
#   type: 'equal', 'replace', 'insert', 'delete'
#   matched_idx: index in old lines (undef if insert)
#   snippet_idx: index in new lines (undef if delete)
sub diff_lines {
    my ($old_lines, $new_lines) = @_;
    my $old_len = scalar @$old_lines;
    my $new_len = scalar @$new_lines;

    # Compute LCS table
    my @lcs;
    for my $i (0..$old_len) {
        for my $j (0..$new_len) {
            $lcs[$i][$j] = 0;
        }
    }

    for my $i (1..$old_len) {
        for my $j (1..$new_len) {
            if ($old_lines->[$i-1] eq $new_lines->[$j-1]) {
                $lcs[$i][$j] = $lcs[$i-1][$j-1] + 1;
            } else {
                $lcs[$i][$j] = ($lcs[$i-1][$j] > $lcs[$i][$j-1]) ? $lcs[$i-1][$j] : $lcs[$i][$j-1];
            }
        }
    }

    # Backtrack to find diff actions
    my @actions;
    my $i = $old_len;
    my $j = $new_len;
    while ($i > 0 || $j > 0) {
        if ($i > 0 && $j > 0 && $old_lines->[$i-1] eq $new_lines->[$j-1]) {
            unshift @actions, { type => 'equal', matched_idx => $i-1, snippet_idx => $j-1 };
            $i--;
            $j--;
        }
        elsif ($j > 0 && ($i == 0 || $lcs[$i][$j-1] >= $lcs[$i-1][$j])) {
            unshift @actions, { type => 'insert', matched_idx => undef, snippet_idx => $j-1 };
            $j--;
        }
        elsif ($i > 0 && ($j == 0 || $lcs[$i][$j-1] < $lcs[$i-1][$j])) {
            unshift @actions, { type => 'delete', matched_idx => $i-1, snippet_idx => undef };
            $i--;
        }
    }

    # Post-process to merge adjacent delete+insert pairs as replace for cleaner output
    my @merged;
    while (@actions) {
        my $act = shift @actions;
        if ($act->{type} eq 'delete' && @actions && $actions[0]{type} eq 'insert') {
            my $ins = shift @actions;
            push @merged, { type => 'replace', matched_idx => $act->{matched_idx}, snippet_idx => $ins->{snippet_idx} };
        } else {
            push @merged, $act;
        }
    }

    return (\@merged);
}

# Tries heuristic, then default filenames, else fallback to snippet.
sub process_snippet_or_file_block {
    my ($type, $block, $fname, $default_filenames_ref) = @_;

    # Add a list of patterns that always indicate a snippet, never a full file
    my @snippet_indicator_patterns = (
	qr/#\s*existing commands\s*\.\.\./i,
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
    my $processed_snippet = preprocess_snippet($block, $type, $fname);
    if (can_splice_snippet($processed_snippet)) {
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
	    $searchargprovided = 1;
	}
        my $candidate = find_splice_target_file($body, $fnamesearch, $type);
	if (! $candidate && $tmpfirst_indent > 0) {
            my $candidate2 = find_splice_target_file($normalized_body, $fnamesearch, $type);
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

	    # Splice snippet with tab awareness
	    my $replacement_block = splice_snippet_with_tab_awareness($matched_block, $indented_body);
            $file_content =~ s/\Q$matched_block\E/$replacement_block/;

            # Write to pending file for patching
            my $out_path = "$change_dir/${idbase}-$n-pending.file";
            write_file_and_log($out_path, $file_content);

            # Generate patch
            my $relative_path = $file_path;
            $relative_path =~ s/^\Q$ws_root\E\/?//;
            make_patch($relative_path, $out_path, "$change_dir/${idbase}-$n-pending.patch");
            write_meta($n, $relative_path, $type);
            $n++;
            return;
        }
    }
    if (defined $fname && "$fname" ne "" && -e "$ws_root/$fname") {
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
    if (defined $fname && "$fname" ne "") {
	process_file_block($fname, $block);
	return;
    }
    notice "No filename found or default filename left; emitting snippet #$n";
    process_snippet_block($type, $block, "$change_dir/${idbase}-$n-pending.snippet");
}

#sub process_diff {
#    my ($diff) = @_;
#    debug "Diff block";
#    my $diffp = "$change_dir/${idbase}-$n-pending.diff";
#    write_file_and_log($diffp, $diff);
#    my $ok = system(qq{cd "$ws_root" && patch --dry-run -p1 < "$diffp"}) == 0;
#    if ($ok) {
#        open my $in, '<', $diffp; local $/; my $d = <$in>; close $in;
#        my $patchp = "$change_dir/${idbase}-$n-pending.patch";
#        write_file_and_log($patchp, $d);
#    }
#    write_meta($n);
#    $n++;
#}

#sub process_shell {
#    my ($shell) = @_;
#    debug "Shell block";
#    my $sp = "$change_dir/${idbase}-$n-pending.sh";
#    write_file_and_log($sp, $shell);
#    write_meta($n);
#    $n++;
#}

sub process_manual {
    my ($txt) = @_;
    debug "Manual block";
    my $mp = "$change_dir/${idbase}-$n-pending.txt";
    write_file_and_log($mp, $txt);
    write_meta($n);
    $n++;
}
