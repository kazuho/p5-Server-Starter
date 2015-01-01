use strict;
use warnings;

use File::Temp ();
use Test::TCP;
use Test::More tests => 28;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

my $tempdir = File::Temp::tempdir(CLEANUP => 1);

for my $signal_on_hup ('TERM', 'USR1') {
    
    test_tcp(
        server => sub {
            my $port = shift;
            start_server(
                port        => $port,
                exec        => [
                    $^X, qw(t/05-killolddelay-echod.pl), "$tempdir/signame",
                ],
                status_file => "$tempdir/status",
                enable_auto_restart => 1,
                auto_restart_interval => 6,
                kill_old_delay => 2,
                ($signal_on_hup ne 'TERM'
                     ? (signal_on_hup => $signal_on_hup) : ()),
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
            # check response and get pid
            is($sock->syswrite("hello"), 5, 'write');
            ok($sock->sysread($buf, 1048576), 'read');
            undef $sock;
            like($buf, qr/^\d+:hello$/, 'read');
            $buf =~ /^(\d+):/;
            my $worker_pid = $1;
            # switch to next gen
            sleep 2;
            my $status = get_status();
            like(get_status(), qr/^1:\d+\n$/s, 'status before auto-restart');
            sleep 7; # new worker spawn at 7 (since start, interval(1) + auto_restart_interval(6)), status updated at 8 (7 + interval(1)), old dies at 11 (8 + kill_old_delay(2) + sleep(1) in the child source code)
            like(get_status(), qr/^1:\d+\n2:\d+$/s, 'status during transient state');
            sleep 3;
            like(get_status(), qr/^2:\d+\n$/s, 'status after auto-restart');
            is(
                do {
                    open my $fh, '<', "$tempdir/signame"
                        or die $!;
                    <$fh>;
                },
                $signal_on_hup,
                'signal sent on hup',
            );
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
    
    ok ! -e "$tempdir/status", 'no more status file';
}

sub get_status {
    open my $fh, '<', "$tempdir/status"
        or die "failed to open file:$tempdir/status:$!";
    do { undef $/; <$fh> };
}
