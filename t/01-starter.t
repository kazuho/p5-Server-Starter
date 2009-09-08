use strict;
use warnings;

use Test::TCP;
use Test::More tests => 9;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

test_tcp(
    server => sub {
        my $port = shift;
        start_server(
            port => $port,
            exec => [ qw(t/01-starter-echod.pl) ],
        );
    },
    client => sub {
        my ($port, $server_pid) = @_;
        my $buf;
        sleep 1;
        my $sock = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
        );
        ok($sock, 'connect');
        # check response and get pid
        is($sock->syswrite("hello"), 5, 'write');
        ok($sock->sysread($buf, 1048576), 'read');
        like($buf, qr/^\d+:hello$/, 'read');
        $buf =~ /^(\d+):/;
        my $worker_pid = $1;
        # switch to next gen
        kill 'HUP', $server_pid;
        sleep 5;
        $sock = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
        );
        ok($sock, 'reconnect');
        is($sock->syswrite("hello"), 5, 'write after switching');
        ok($sock->sysread($buf, 1048576), 'read after switching');
        like($buf, qr/^\d+:hello$/, 'read after swiching (format)');
        isnt($buf, "$worker_pid:hello", 'pid should have changed');
    },
);
