use strict;
use warnings;
use Test::More;
use Test::Requires qw(IO::Socket::IP);
use Test::TCP;
use Server::Starter qw(start_server);

sub doit {
    my ($bind_addr, $other_addr) = @_;
    test_tcp(
        server => sub {
            my $port = shift;
            start_server(
                port        => $port,
                exec        => [
                    $^X, qw(t/10-bindaddr-server.pl),
                ],
            );
        },
        client => sub {
            my $port = shift;
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
        },
    );
}

subtest "v4" => sub {
    doit("127.0.0.1", "::1");
};

done_testing;
