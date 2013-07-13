use strict;
use warnings;

use File::Temp ();
use Test::TCP;
use Test::More tests => 7;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

my $tempdir = File::Temp::tempdir(CLEANUP => 1);

# Prepare envdir
mkdir "$tempdir/env" or die $!;
open my $envfh, ">", "$tempdir/env/FOO" or die $!;
print $envfh "foo-value1";
close $envfh;
undef $envfh;
sleep 1;

test_tcp(
    server => sub {
        my $port = shift;
        start_server(
            port        => $port,
            exec        => [
                $^X, qw(t/07-envdir-print.pl),
            ],
            status_file => "$tempdir/status",
            envdir => "$tempdir/env",
        );
    },
    client => sub {
        my ($port, $server_pid) = @_;
        my $buf;
        #sleep 1;
        my $sock = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
        );
        ok($sock, 'connect');
        # check response
        ok($sock->sysread($buf, 1048576), 'read');
        undef $sock;
        # Initial worker does not read envdir
        unlike($buf, qr/^FOO=foo-value1$/m, 'changed env');
        # rewrite envdir
        open my $envfh, ">", "$tempdir/env/FOO" or die $!;
        print $envfh "foo-value2";
        close $envfh;
        undef $envfh;
        # switch to next gen
        sleep 1;
        kill "HUP", $server_pid;
        sleep 2;
        $sock = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
        );
        ok($sock, 'reconnect');
        # check response
        ok($sock->sysread($buf, 1048576), 'read');
        undef $sock;
        # new worker reads the rewritten envdir
        like($buf, qr/^FOO=foo-value2$/m, 'changed env');
    },
);

ok ! -e "$tempdir/status", 'no more status file';
