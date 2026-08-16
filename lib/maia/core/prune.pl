#!/usr/bin/env perl
#
# Copyright (c) 2025 Ola Lundqvist <ola@inguza.com>
#
use strict;
use warnings;

# Usage:
#   prune.pl <id>
#
# Reads content from STDIN, removes fenced code blocks (```...```) and
# blockquote blocks (lines starting with '>'), replacing each removed block
# with <<BLOCK #id: pruned>> placeholders.
#
# Outputs the pruned content to STDOUT.

my $id = shift;
if ( "$id" eq "") {
    die "Usage: $0 <id>\n";
}

my @lines = <STDIN>;

my @output;
my $in_fence = 0;
my $fence_delim = '';
my $in_blockquote = 0;

sub flush_blockquote {
    if ($in_blockquote) {
        push @output, "<<BLOCK #$id: pruned>>\n";
        $in_blockquote = 0;
    }
}

sub flush_fence {
    # When a fenced code block ends, insert a placeholder
    push @output, "<<BLOCK #$id: pruned>>\n";
}

for my $line (@lines) {
    if (!$in_fence && $line =~ /^```/) {
        $in_fence = 1;
        $fence_delim = '```';
        next;
    }
    elsif ($in_fence && $line =~ /^$fence_delim/) {
        $in_fence = 0;
        flush_fence();
        next;
    }
    if ($in_fence) {
        next;
    }

    if ($line =~ /^>/) {
        $in_blockquote = 1;
        next;
    }
    else {
        flush_blockquote();
        push @output, $line;
    }
}

flush_blockquote();

print for @output;
