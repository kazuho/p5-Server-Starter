use strict;
use warnings;
use Test::More;
use Test::Requires qw(IO::Socket::IP);
use Net::EmptyPort qw(can_bind empty_port);
use Server::Starter qw(start_server);

plan skip_all => 'IPv6 not available'
    unless can_bind('::1');

my $port = empty_port;

sub doit {
    my ($bind_addr, $other_addr) = @_;
    my $pid = fork;
    die "fork failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        # server
        start_server(
            port        => "[$bind_addr]:$port",
            exec        => [
                $^X, qw(t/10-bindaddr-server.pl),
            ],
        );
        exit 0;
    }
    # client
    sleep 1;
    my $sock = IO::Socket::IP->new(
        PeerHost => $bind_addr,
        PeerPort => $port,
        Proto    => 'tcp',
    );
    ok($sock, "connected to bindaddr");
    $sock->sysread(my $buf, 1024); # wait for disconnect
    undef $sock;
    $sock = IO::Socket::IP->new(
        PeerHost => $other_addr,
        PeerPort => $port,
        Proto    => 'tcp',
    );
    ok ! defined $sock, "cannot connect to other addr";
    kill 'TERM', $pid;
    wait();
}

subtest "v4" => sub {
    doit("127.0.0.1", "::1");
};
subtest "v6" => sub {
    doit("::1", "127.0.0.1");
};

done_testing;
