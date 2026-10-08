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
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Encode qw(decode FB_CROAK);
use MIME::Base64 qw(encode_base64);
use Getopt::Long;

# Globals
my $workspace = '.';
my $mcp_cache = '';

# Parse options
GetOptions(
    'workspace=s'      => \$workspace,
    'mcpcache=s'       => \$mcp_cache,
    'help'             => sub { usage(); exit(0) },
) or usage_and_exit();

my @file_specs = @ARGV;

my @result = ();
# Main. Process specifications in stages: @ source handling, path resolution,
# content detection, and only then type-specific selector interpretation.
foreach my $spec (@file_specs) {
    if (index($spec, '@') >= 0) {
        my ($url_spec, $url) = split(/@/, $spec, 2);
        my $url_record = parse_url_spec($url_spec, $url);
        if (!defined $url_record) {
            warn "Warning: Invalid URL file specification '$spec'. Skipping.\n";
            next;
        }
        push @result, $url_record;
        next;
    }

    my ($file_spec, $filter_cmd) = split(/\|/, $spec, 2);
    my ($filepath, $fullpath, $rest_spec);
    my $is_mcp = index($file_spec, '#') >= 0;

    if ($is_mcp) {
        # MCP specifications are opaque. The original spec, including a
        # possible filter, is the cache identity used by common.sh.
        $filepath = $file_spec;
        if ($mcp_cache eq '') {
            warn "Warning: No MCP cache directory was supplied for '$spec'. Skipping.\n";
            next;
        }
        my $cache_id = substr(sha256_hex($spec), 0, 16);
        $fullpath = File::Spec->catfile($mcp_cache, "$cache_id.mcp");
        $rest_spec = undef;
    } else {
        # Only the path is separated before reading. The remaining colon
        # fields cannot be interpreted until the file type is known.
        ($filepath, $rest_spec) = split(/:/, $file_spec, 2);
        $fullpath = File::Spec->rel2abs($filepath, $workspace);
    }

    if (!-f $fullpath) {
        warn "Warning: File '$fullpath' does not exist or is not a regular file. Skipping.\n";
        next;
    }

    my $type = "";
    my $mime;
    my $content;
    my $quality;
    my @items = (!$is_mcp && defined($rest_spec) && length($rest_spec))
        ? split(/:/, $rest_spec) : ();

    # An explicit type overrides autodetection. Only after this step can the
    # remaining item be interpreted as a selector or resolution.
    my $detected_mime;
    if (@items && $items[0] =~ /^(text|image|document|other)$/i) {
        $type = lc shift @items;
        # Explicit binary types still need their MIME type for provider
        # serializers.  Text does not need a data-URL MIME type here.
        $detected_mime = detect_mime($fullpath)
            if $type ne 'text';
    }
    else {
	($type, $detected_mime) = read_and_classify($fullpath);
    }
    
    if ($type eq 'image' || $type eq 'document') {
	$content = read_binary_file($fullpath);
        if (@items && $items[0] =~ /^(low|medium|high)$/i) {
            $quality = lc shift @items;
        }
        if (@items) {
            warn "Warning: Unexpected selector for $type file '$filepath'. Skipping.\n";
            next;
        }
    } elsif ($type eq 'other') {
	$content = read_binary_file($fullpath);
        if (@items) {
            warn "Warning: Unexpected selector for other file '$filepath'. Skipping.\n";
            next;
        }
    } elsif ($type eq 'text') {
        my $selector = join(':', @items);
        my ($language, $extraction_type, $identifier) =
            parse_text_selector($selector);
        if ($extraction_type eq 'function') {
            $content = extract_bash_function($fullpath, $identifier)
                if $language eq 'bash';
            if (!defined $content || $language ne 'bash') {
                warn "Warning: Function '$identifier' not supported or not found in '$filepath'. Skipping.\n";
                next;
            }
        } elsif ($extraction_type eq 'lines') {
            $content = extract_lines($fullpath, $identifier);
            if (!defined $content) {
                warn "Warning: Invalid line range '$identifier' in file '$filepath'. Skipping.\n";
                next;
            }
        } elsif ($extraction_type ne 'full') {
            warn "Warning: Unsupported extraction type '$extraction_type'. Skipping.\n";
            next;
        }
	else {
	    $content = extract_full_file($fullpath);
	}
    }

    if (defined $filter_cmd && $filter_cmd ne '') {
        my ($filtered_content, $filter_status) = run_filter($filter_cmd, $content);
        if ($filter_status != 0) {
            warn "Warning: Filter command '$filter_cmd' failed with exit code $filter_status. Skipping.\n";
            next;
        }
        $content = $filtered_content;
    }
    if ($type eq "text") {
	my %record = (filename => $filepath, type => $type, content => $content);
	push @result, \%record;
    }
    else {
	$content = encode_base64($content, '');
	my %record = (filename => $filepath, type => $type, base64 => $content);
	$record{mime} = $detected_mime if defined $detected_mime && $detected_mime ne '';
	$record{quality} = $quality if defined $quality;
	push @result, \%record;
    }
}
print encode_json(\@result);
print "\n";

exit(0);

# --- Functions ---

sub usage {
    print <<"EOF";
Usage: extract.pl [--workspace DIR] [--mcpcache DIR] <file_spec> [<file_spec> ...]

File spec format is described in docs/filespecs.md
EOF
}

sub usage_and_exit {
    usage();
    exit(1);
}

# Parse a provider URL specification. The URL itself is opaque.
# The long form is name/path:type:quality@url. The short form
# name/path:quality@url infers image/document from the filename extension.
sub parse_url_spec {
    my ($spec, $url) = @_;
    return undef unless defined $url && length $url;

    my @parts = split /:/, $spec, 3;
    my $filename = shift @parts;
    return undef unless defined $filename && length $filename;

    my ($type, $quality);
    if (@parts == 2) {
        ($type, $quality) = @parts;
    } elsif (@parts == 1) {
        ($quality) = @parts;
        if ($filename =~ /\.(?:png|jpe?g|gif|webp|bmp|tiff?)$/i) {
            $type = 'image';
        } elsif ($filename =~ /\.(?:pdf|docx?|rtf|odt|epub)$/i) {
            $type = 'document';
        } else {
            return undef;
        }
    } else {
        return undef;
    }

    return undef unless defined $type && $type =~ /^(image|document)$/i;
    if (defined $quality && $quality ne '') {
        return undef unless $quality =~ /^(low|medium|high)$/i;
        $quality = lc($quality);
    }

    my %record = (
        filename => $filename,
        type     => lc($type),
        url      => $url,
    );
    $record{quality} = $quality if defined $quality && $quality ne '';
    return \%record;
}

# Parse a local file specification according to docs/filespecs.md.
# MCP specifications are handled before this function and are intentionally
# never passed here, since ':' and '|' are valid URI characters.
sub parse_local_spec {
    my ($spec, $workspace) = @_;
    my @parts = split /:/, $spec, 4;
    return undef unless @parts && defined $parts[0] && length $parts[0];

    my $filepath = shift @parts;
    my ($type, $quality, $rest);
    my $first = shift @parts;

    if (defined $first && $first =~ /^(text|image|document|other)$/i) {
        $type = lc $first;
        $rest = join(':', @parts);
        if (($type eq 'image' || $type eq 'document') && defined $rest && $rest ne '') {
            ($quality, $rest) = split(/:/, $rest, 2);
        }
    } elsif (defined $first) {
        # Without an explicit type, the remaining selector or resolution is
        # interpreted after automatic type detection.
        $rest = join(':', grep { defined } ($first, @parts));
    }

    if (defined $quality && $quality !~ /^(low|medium|high)$/i) {
        return undef;
    }
    return {
        filepath => $filepath,
        type     => $type,
        quality  => defined($quality) ? lc($quality) : undef,
        rest     => (defined($rest) && $rest ne '') ? $rest : undef,
    };
}

# Classify a file by inspecting only a bounded prefix.  This must not read
# the complete file: text selectors may later read only a small portion.
# NUL bytes, invalid UTF-8, or an excessive number of control characters in
# the sample identify a binary file.  Only binary files are passed to file(1).
sub read_and_classify {
    my ($file) = @_;
    my $sample_size = 65536;
    open my $fh, '<:raw', $file or do {
        warn "Failed to open file '$file': $!\n";
        return 'other';
    };

    my $bytes = '';
    my $read = read($fh, $bytes, $sample_size);
    close $fh;
    if (!defined $read) {
        warn "Failed to read file '$file': $!\n";
        return 'other';
    }

    my $binary = index($bytes, "\0") >= 0;
    if (!$binary) {
        my $text;
        $binary = 1 unless eval {
            $text = decode('UTF-8', $bytes, FB_CROAK);
            1;
        };
        if (!$binary) {
            my $controls = () = $text =~ /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g;
            $binary = 1 if length($text) && $controls > length($text) / 100;
        }
    }

    return classify_binary($file) if $binary;
    return ('text', 'text/plain');
}

# Read a file without decoding it. This is used when a binary filter needs
# the original bytes on stdin.
sub read_binary_file {
    my ($file) = @_;
    open my $fh, '<:raw', $file or return undef;
    local $/;
    my $content = <$fh> // '';
    close $fh;
    return $content;
}

sub run_filter {
    my ($filter_cmd, $content) = @_;
    my $filtered_content = '';
    require IPC::Open2;
    my $pid = IPC::Open2::open2(my $out, my $in, 'sh', '-c', $filter_cmd);
    print $in $content;
    close $in;
    { local $/; $filtered_content = <$out> // ''; }
    waitpid($pid, 0);
    return ($filtered_content, $? >> 8);
}

# Run file only after the inexpensive in-process binary test says that the
# content is binary.
sub detect_mime {
    my ($file) = @_;
    my $mime = '';
    if (open my $fh, '-|', 'file', '--brief', '--mime-type', '--', $file) {
        local $/;
        $mime = <$fh> // '';
        close $fh;
        $mime =~ s/[\r\n]+\z//;
    }
    if ("$mime" eq "") {
	# Fallback if mime is not available
	if (open my $fh, '-|', 'od', '-An', '-N12', '-tx1', $file) {
	    local $/;
	    my $hex = <$fh> // '';
	    close $fh;
	    if ($hex =~ /^89504e470d0a1a0a89504e470d0a1a0a/) {
		$mime = "image/png";
	    }
	    elsif ($hex =~ /^ffd8ff/) {
		$mime = "image/png";
	    }
	    elsif ($hex =~ /^474946383761/ || $hex =~ /^474946383961/) {
		$mime = "image/gif";
	    }
	    elsif ($hex =~ /^52494646........57454250/) {
		$mime = "image/webp";
	    }
	    elsif ($hex =~ /^255044462d/) {
		$mime = "image/zip";
	    }
	    elsif ($hex =~ /^1f8b/) {
		$mime = "image/gzip";
	    }
	    else {
		$mime = "application/octet-stream";
	    }
	}
    }
    if ("$mime" eq "") {
	$mime = "application/octet-stream";
    }
    return $mime;
}

sub classify_binary {
    my ($file) = @_;
    my $mime = detect_mime($file);
    my $type = 'other';
    $type = 'image' if $mime =~ m{^image/}i;
    $type = 'document' if $mime =~ m{^(application/pdf|application/(msword|rtf|postscript|epub\+zip|vnd\.)|text/rtf)}i;
    return ($type, $mime);
}

# Parse the selector belonging to a text file.
sub parse_text_selector {
    my ($selector) = @_;
    return ('bash', 'full', 'all') if !defined($selector) || $selector eq '' || $selector eq 'full';
    return ('bash', 'lines', $selector) if $selector =~ /^\d+(?:-\d+)?$/;

    my @parts = split /:/, $selector;
    my $language = 'bash';
    if (@parts && $parts[0] =~ /^(bash|c|php|python)$/i) {
        $language = lc shift @parts;
    }
    my $matchtype = 'function';
    if (@parts && $parts[0] eq 'function') {
        $matchtype = lc shift @parts;
    }
    my $identifier = join(':', @parts);
    return ($language, $matchtype, $identifier);
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
