use strict;
use warnings;

use File::Temp ();
use Test::TCP;
use Test::More tests => 4;

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
        #sleep 1;
        my $fetch_env = sub {
            my $sock = IO::Socket::INET->new(
                PeerAddr => "127.0.0.1:$port",
                Proto    => 'tcp',
            ) or die $!;
            my $buf;
            $sock->sysread($buf, 1048576)
                or die $!;
            undef $sock;
            $buf;
        };
        my $restart = sub {
            sleep 1;
            kill "HUP", $server_pid;
            sleep 2;
        };
        # Initial worker does not read envdir
        my $buf = $fetch_env->();
        ok($buf !~ qr/^FOO=foo-value1$/m, 'changed env');
        # rewrite envdir
        open my $envfh, ">", "$tempdir/env/FOO" or die $!;
        print $envfh "foo-value2";
        close $envfh;
        undef $envfh;
        # switch to next gen
        $restart->();
        # new worker reads the rewritten envdir
        $buf = $fetch_env->();
        ok($buf =~ /^FOO=foo-value2$/m, 'changed env');
        # remove the env file and check that the removal gets reflected
        unlink "$tempdir/env/FOO"
            or die $!;
        # switch to next gen
        $restart->();
        # new worker reads the rewritten envdir
        $buf = $fetch_env->();
        ok($buf !~ /^FOO=foo-value2$/m, 'removed env');
    },
);

ok ! -e "$tempdir/status", 'no more status file';
