use strict;
use warnings;

use File::Temp ();
use Test::TCP;
use Test::More tests => 4;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

test_tcp(
    server => sub {
        my $port = shift;
        start_server(
            port        => "$port=0",
            exec        => [
                $^X, qw(t/11-specified-fd-server.pl)
            ],
        );
        exit 0;
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
        # check response and get pid
        is($sock->syswrite("hello"), 5, 'write');
        ok($sock->sysread($buf, 1048576), 'read');
        undef $sock;
        like($buf, qr/^\d+:hello$/, 'read');
        kill $server_pid;
    },
);

