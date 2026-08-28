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
use JSON::PP;
use Getopt::Long;
# Use the common.pm in the same directory
use FindBin qw($Bin);
use lib $Bin;
use common;

# Parse options
my $loglevel;
GetOptions(
    'loglevel|l=s' => \$loglevel
    ) or die_log "Invalid options\n";

# Set TERM_LOGLEVEL (default NOTICE)
$ENV{TERM_LOGLEVEL} = $loglevel
    ? uc $loglevel
    : ($ENV{TERM_LOGLEVEL} // 'NOTICE');

# Expect at 5 positional args
my $argc = scalar @ARGV;
if ($argc != 5) {
    print "#arguments: $argc\n";
    die_log "Usage: $0 [--loglevel LEVEL] <source-file> <target-file> <change-json-file> <fallback-txt-description-file> <ws-root>";
}

# We expect first positional argument to be command: parse or process
my $filename = shift @ARGV;
my $targetfile = shift @ARGV;
my $changefile = shift @ARGV;
my $txtfile = shift @ARGV;

my $ws_root = shift @ARGV;
my $sourcefile = "$ws_root/$filename";

my $source = &read_file("$sourcefile");
my $change = &read_json_file("$changefile");

# We use a global variable here, not the nicest but it works well enough
# for this small tool.
my $error = "";
my $content = &change_file($source, $change);
print $error;
&write_file($targetfile, $content);

exit 0;

###############################################################
################# Help Functions ##############################
###############################################################

sub change_file {
    my ($content, $change) = @_;
    
    if (ref($change) ne 'ARRAY') {
	$error = "No changes provided.\n";
	return;
    }

    my $sep = "";
    my $i = 0;
    for my $item (@$change) {
	$i++;
	if (ref($item) ne 'HASH') {
	    $error = "Change $i is not a change. Aborting.\n";
	    last;
	}
	for my $key (qw(old new)) {
	    if (!exists $item->{$key}) {
		$error = "Change $i is missing '$key'. Aborting.\n";
		last;
	    }
	}
        my $old = $item->{'old'};
	if ($old eq "") {
	    $error = "Change $i has an empty string to remove. Aborting.\n";
	    last;
	}
        my $new = $item->{'new'};

	# Find the old text and substitute
	my $pos = index($content, $old);
	if ($pos < 0) {
	    # The LLM may include a trailing newline in the 'old' text even when the
	    # actual file does not end with a newline. In that case we can try a safe
	    # fallback: if 'old' ends with a newline, strip the final newline from
	    # both 'old' and 'new' and check whether that variant matches exactly at
	    # the end of the file. Only accept this EOF-only match to avoid accidental
	    # mid-file replacements.
	    if ($old =~ /\n\z/) {
		my $old_no_nl = $old;
		$old_no_nl =~ s/\n\z//;
		my $new_no_nl = $new;
		$new_no_nl =~ s/\n\z//;
		my $rpos = rindex($content, $old_no_nl);
		if ($rpos >= 0 && $rpos + length($old_no_nl) == length($content)) {
		    # Found match at EOF without trailing newline. Replace that region.
		    substr($content, $rpos, length($old_no_nl)) = $new_no_nl;
		    next;
		}
	    }

	    $error = "Change $i: old text not found. Skipping.\n";
	    # Provide diagnostics
	    open TF, ">>$txtfile";
	    print TF "Change $i. Could not find the exact old text. Please replace the following text manually:\n";
	    print TF "---- Old text to replace ----\n";
	    print TF "$old\n";
	    print TF "---- End ----\n";
	    print TF "\n";
	    print TF "---- New replacement text ----\n";
	    print TF "$new\n";
	    print TF "---- End ----\n";
	    close(TF);
	    next;
	}
	substr($content, $pos, length($old)) = $new;
    }
    
    return $content;
}
