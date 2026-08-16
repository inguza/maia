#!/usr/bin/env perl
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
use strict;
use warnings;
use File::Spec;
use Getopt::Long;

# Globals
my $workspace = '.';

# Parse options
GetOptions(
    'workspace=s' => \$workspace,
    'help'       => sub { usage(); exit(0) },
) or usage_and_exit();

my @file_specs = @ARGV;
if (!@file_specs) {
    print STDERR "Error: No file specifications provided.\n";
    usage_and_exit();
}

# Main
foreach my $spec (@file_specs) {
    # Detect and split pipe filter syntax
    my ($file_spec, $filter_cmd) = split(/\|/, $spec, 2);

    my ($filepath, $language, $extraction_type, $identifier) = parse_file_spec($file_spec);

    # Default values
    $language ||= 'bash';
    if (!defined $extraction_type) {
        if (!defined $identifier) {
            $extraction_type = 'full';
            $identifier = 'all';
        } elsif ($identifier =~ /^\d+(-\d+)?$/) {
            $extraction_type = 'lines';
        } else {
            $extraction_type = 'function';
        }
    }

    # Resolve full path
    my $fullpath = File::Spec->rel2abs($filepath, $workspace);
    if (!-f $fullpath) {
        warn "Warning: File '$fullpath' does not exist or is not a regular file. Skipping.\n";
        next;
    }

    my $content = '';
    if ($language eq 'bash') {
	if ($extraction_type eq 'function') {
	    $content = extract_bash_function($fullpath, $identifier);
	    if (!defined $content) {
		warn "Warning: Function '$identifier' not found in file '$filepath'. Skipping.\n";
		next;
	    }
	} elsif ($extraction_type eq 'lines') {
	    $content = extract_lines($fullpath, $identifier);
	    if (!defined $content) {
		warn "Warning: Invalid line range '$identifier' in file '$filepath'. Skipping.\n";
		next;
	    }
	} elsif ($extraction_type eq 'full') {
	    $content = extract_full_file($fullpath);
	} else {
	    warn "Warning: Unsupported extraction type '$extraction_type' for bash. Skipping.\n";
	    next;
	}
    } else {
	# Unsupported language fallback: only full file extraction
	if ($extraction_type eq 'full') {
	    $content = extract_full_file($fullpath);
	} else {
	    warn "Warning: Language '$language' with extraction type '$extraction_type' not supported yet. Skipping.\n";
	    next;
	}
    }
    # | filters are always done after the :filter or full file extraction
    if (defined $filter_cmd) {
        # Pipe content through the filter command
        # Use open3 or open with pipe from command
        # Use shell to interpret complex commands
        my $filtered_content = '';
        {
            use IPC::Open2;
            my $pid = open2(my $out, my $in, "sh", "-c", $filter_cmd);
            print $in $content;
            close $in;
            {
                local $/;
                $filtered_content = <$out>;
            }
            waitpid($pid, 0);
            my $exit_status = $? >> 8;
            if ($exit_status != 0) {
                warn "Warning: Filter command '$filter_cmd' failed with exit code $exit_status. Skipping.\n";
                next;
            }
        }
        $content = $filtered_content;
    }

    # Print output with bracket header
    my $out = "[$filepath $extraction_type $identifier]\n";
    $out =~ s/ full all//;
    print $out;
    print '```'."\n"; # Fence the content
    print $content;
    # Ensure ending with newline
    print "\n" unless $content =~ /\n\z/;
    print '```'."\n"; # End fence
}

exit(0);

# --- Functions ---

sub usage {
    print <<"EOF";
Usage: extract.pl [--workspace DIR] <file_spec> [<file_spec> ...]

Each <file_spec> has the format:
  filepath[:language][:extraction_type]:identifier

  - filepath: path to file (relative to workspace or absolute)
  - language: optional, e.g. bash, python (default: bash)
  - extraction_type: optional, one of 'function', 'lines', 'full'
  - identifier:
      * For function: function name
      * For lines: line number or range (e.g. 100, 50-60)
      * For full: 'all' or omit identifier

Examples:
  lib/change.sh:change_usage
  lib/change.sh:bash:function:change_usage
  lib/change.sh:lines:100-120
  lib/change.sh:100-120
  lib/change.sh:full:all
EOF
}

sub usage_and_exit {
    usage();
    exit(1);
}

# Parse file spec string into parts
sub parse_file_spec {
    my ($spec) = @_;
    my @parts = split /:/, $spec, 4;

    # Depending on number of parts, assign accordingly
    my ($filepath, $language, $extraction_type, $identifier, $part2, $part3);

    if (@parts == 1) {
        ($filepath) = @parts;
    } elsif (@parts == 2) {
        ($filepath, $part2) = @parts;
        # Decide if $part2 is language/extraction/identifier
        if ($part2 =~ /^(bash|python|php|c|perl)$/i) {
            $language = lc $part2;
        } else {
            $identifier = $part2;
        }
    } elsif (@parts == 3) {
        ($filepath, $language, $part3) = @parts;
        if ($language !~ /^(bash|python|php|c|perl)$/i) {
            # Shift parts if language not recognized
            $identifier = $part3;
            $extraction_type = $language;
            $language = undef;
        } else {
            $language = lc $language;
            $extraction_type = lc $part3;
        }
    } elsif (@parts == 4) {
        ($filepath, $language, $extraction_type, $identifier) = @parts;
        $language = lc $language;
        $extraction_type = lc $extraction_type;
    }

    return ($filepath, $language, $extraction_type, $identifier);
}

# Extract full file content
sub extract_full_file {
    my ($file) = @_;
    open my $fh, '<', $file or do {
        warn "Failed to open file '$file': $!";
        return;
    };
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# Extract specified lines (single line or range)
sub extract_lines {
    my ($file, $line_spec) = @_;
    my ($start, $end);
    if ($line_spec =~ /^(\d+)-(\d+)$/) {
        ($start, $end) = ($1, $2);
        return undef if $start > $end;
    } elsif ($line_spec =~ /^(\d+)$/) {
        $start = $end = $1;
    } else {
        return undef;
    }

    open my $fh, '<', $file or do {
        warn "Failed to open file '$file': $!";
        return;
    };

    my @lines;
    my $lineno = 0;
    while (my $line = <$fh>) {
        $lineno++;
        if ($lineno >= $start && $lineno <= $end) {
            push @lines, $line;
        }
        last if $lineno > $end;
    }
    close $fh;

    return join('', @lines);
}

# Extract bash function by name
sub extract_bash_function {
    my ($file, $func_name) = @_;
    open my $fh, '<', $file or do {
        warn "Failed to open file '$file': $!";
        return;
    };

    my $in_function = 0;
    my $brace_count = 0;
    my $function_text = '';

    # Regex to detect function start:
    # Matches: funcname() {  or function funcname {  or funcname() \n {
    # We'll accept funcname() { on same line or next line brace
    my $func_start_regex = qr/^\s*(function\s+)?\Q$func_name\E\s*\(\)\s*\{|^\s*function\s+\Q$func_name\E\s*\{/;

    # We'll read ahead one line to detect brace on next line if needed.
    my @buffer = ();

    # Helper to check if a character is inside quotes or comments to ignore braces inside them
    sub clean_line_for_braces {
        my ($line) = @_;
        # Remove comments starting with unquoted #
        # Remove strings (single and double quoted)
        my $clean = '';
        my $len = length($line);
        my $in_sq = 0;
        my $in_dq = 0;
        for (my $i=0; $i<$len; $i++) {
            my $c = substr($line, $i, 1);
            if ($c eq "'" && !$in_dq) {
                $in_sq = !$in_sq;
                $clean .= ' '; # replace quote with space
            } elsif ($c eq '"' && !$in_sq) {
                $in_dq = !$in_dq;
                $clean .= ' ';
            } elsif ($c eq '#' && !$in_sq && !$in_dq) {
                last; # comment start: ignore rest of line
            } else {
                $clean .= $c;
            }
        }
        return $clean;
    }

    my $line;
    while ($line = <$fh>) {
        push @buffer, $line;
        if (!$in_function) {
            # Check for function start
            if ($line =~ $func_start_regex) {
                $in_function = 1;
                # Initialize brace count with count of '{' minus '}' on this line (cleaned)
                my $clean = clean_line_for_braces($line);
                my $open = () = $clean =~ /\{/g;
                my $close = () = $clean =~ /\}/g;
                $brace_count = $open - $close;
                $function_text = join('', @buffer);
                @buffer = ();
                # If brace_count == 0, function body hasn't started yet; continue
                next;
            } else {
                shift @buffer if @buffer > 1; # keep buffer max size 1 before function found
            }
        } else {
            # Inside function: accumulate lines and update brace count
            my $clean = clean_line_for_braces($line);
            my $open = () = $clean =~ /\{/g;
            my $close = () = $clean =~ /\}/g;
            $brace_count += $open - $close;
            $function_text .= $line;
            if ($brace_count <= 0) {
                # Function ended
                close $fh;
                return $function_text;
            }
        }
    }
    close $fh;
    return; # function not found or incomplete
}
