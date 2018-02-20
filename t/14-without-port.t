use strict;
use warnings;

use File::Temp ();
use Test::More tests => 2;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

my $tempdir = File::Temp::tempdir(CLEANUP => 1);

my $pid = fork;
unless ($pid) {
    start_server(
        exec => [
            $^X, qw(t/14-without-port-env.pl), "$tempdir/env",
        ],
    );
    exit 0;
};
sleep 1;
kill 'TERM', $pid;
sleep 1;

open my $fh, '<', "$tempdir/env"
    or die "failed to open file:$tempdir/env:$!";
my $log = do { undef $/; <$fh> };
like $log, qr/^env: found$/m;
like $log, qr/^server_ports: empty$/m;
