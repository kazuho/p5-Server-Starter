use strict;
use warnings;

use Test::TCP;
use Test::More tests => 12;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

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
        my ($port, $server_pid) = @_;
        # send USR2 to server to indicate that the worker is ready
        sleep 1;
        kill 'USR2', $server_pid;
        sleep 1;
        my $buf;
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
        # start switching to next gen
        kill 'USR1', $server_pid;
        is($sock->syswrite("hello"), 5, 'write after starting to swtich');
        ok($sock->sysread($buf, 1048576), 'read after starting to switch');
        is($buf, "$worker_pid:hello", 'read after starting to switch');
        # and finally switch
        kill 'USR2', $server_pid;
        sleep 1;
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
