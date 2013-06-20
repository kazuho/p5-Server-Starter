use strict;
use warnings;

use File::Temp ();
use Test::More tests => 1;
use Net::EmptyPort qw/empty_port/;
use IO::Select;
use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

pipe my $logrh, my $logwh
    or die "Died: failed to create pipe:$!";
my $port = empty_port
    or die "could not get any port";
my $tempdir = File::Temp::tempdir(CLEANUP => 0);
open(my $fh, '>', "$tempdir/dir_status") or die "$!";
close($fh);

my $pid = fork;

if ( ! defined $pid ) {
    die "Died: fork failed: $!";
}
elsif ( $pid == 0 ) {
    close $logrh;
    open STDOUT, '>&', $logwh
        or die "Died: failed to redirect STDOUT";
    close $logwh;
    start_server(
        port => $port, #not use
        exec        => [
            $^X, '-e', 'printf "%s\n", -f "dir_status" ? "OK" : "NG"; sleep(1)'
        ],
        dir => $tempdir
    );
    exit(255);
}

close $logwh;
my $result;
my $s = IO::Select->new($logrh);
my @ready = $s->can_read(10);
die "could not read logs from pipe" unless @ready;
sysread($logrh, my $buf, 65536);
like($buf, qr/OK\W/);

kill 'TERM', $pid;
while (wait != $pid) {}

unlink "$tempdir/status";
rmdir $tempdir;


