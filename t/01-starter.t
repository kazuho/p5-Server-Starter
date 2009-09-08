use strict;
use warnings;

use Test::TCP;
use Test::More tests => 3;

use Server::Starter qw(start_server);

test_tcp(
    server => sub {
        my $port = shift;
        print STDERR "starting server on port $port\n";
        start_server(
            port => $port,
            argv => [ qw(t/01-starter-echod.pl) ],
        );
    },
    client => sub {
        my $port = shift;
        my $sock = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
        );
        ok($sock, 'connect');
        is($sock->syswrite("hello\n"), 6, 'write');
        my $buf;
        $sock->sysread($buf, 1048576);
        is($buf, "hello\n", 'read');
    },
);
