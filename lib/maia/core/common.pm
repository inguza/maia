# We do NOT use package concept because then we have to update parse.pl too much
# package common;

use strict;
use warnings;

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

sub read_file {
    my ($path) = @_;
    open my $f, '<', $path or warn_log("Cannot open file $path: $!");
    local $/;
    my $content = <$f>;
    close $f;
    return $content;
}

sub read_json_file {
    my ($path) = @_;
    my $content = &read_file($path);
    my $json = JSON::PP->new->decode($content);
    return $json;
}

sub write_file {
    my ($path, $content) = @_;
    open my $of, '>', $path
        or die_log "Can't write '$path': $!";
    print $of $content;
    close $of;
}

1;
