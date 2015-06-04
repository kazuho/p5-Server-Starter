use strict;
use warnings;
use utf8;
use Test::More;
use Server::Starter qw(start_server restart_server stop_server); 
use File::Temp qw(tempdir);
use Test::TCP;

plan tests => 2;

my $dir = tempdir( CLEANUP => 1 );
my $pidfile = "$dir/pid";

test_tcp(
   server => sub {
        my $port = shift;

        start_server(
            pid_file  => $pidfile,
            daemonize => 1,
            port      => $port,
            exec      => [ $^X, 't/12-stop-server.pl' ],
        );
        exit 0;
    },
    client => sub {
        my $port = shift;

        while (!-s $pidfile) {
            note 'pid file is not available';
            sleep 1; # wait pid file
        }

        my $pid = do {
            open my $fh, '<', $pidfile
                or die "Cannot open $pidfile: $!";
            local $/;
            <$fh>;
        };
        note "PID=$pid";
        is(kill(0, $pid), 1, 'there is a process');

        stop_server(
            pid_file => $pidfile,
            port => $port,
        );
        ok((!-e $pidfile), 'pid file was unlinked');
    },
);

