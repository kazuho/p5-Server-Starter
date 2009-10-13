use strict;
use warnings;

use Test::TCP;
use Test::More tests => 9;

use Server::Starter qw(start_server);

test_tcp(
    server => sub {
        my $port = shift;
        start_server(
            port     => $port,
            exec     => [ $^X, qw(t/02-startfail-server.pl) ],
        );
    },
    client => sub {
        my ($port, $server_pid) = @_;
        my $buf;
        sleep 3;
        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => "127.0.0.1:$port",
                Proto    => 'tcp',
            );
            ok($sock, 'connect');
            # check generation
            ok($sock->sysread($buf, 1048576), 'read');
            is($buf, 2, 'check generation');
        }
        # request restart, that will fail
        kill 'HUP', $server_pid;
        sleep 1;
        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => "127.0.0.1:$port",
                Proto    => 'tcp',
            );
            ok($sock, 'connect');
            ok(
                $sock->sysread($buf, 1048576),
                'read while worker is failing to reboot',
            );
            is($buf, 2, 'check generation');
        }
        # wait until server succeds in reboot
        sleep 5;
        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => "127.0.0.1:$port",
                Proto    => 'tcp',
            );
            ok($sock, 'connect');
            ok(
                $sock->sysread($buf, 1048576),
                'read after worker succeeds to reboot',
            );
            is($buf, 5, 'check generation');
        }
    },
);
