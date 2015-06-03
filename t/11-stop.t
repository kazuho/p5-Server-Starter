use strict;
use warnings;
use utf8;
use Test::More;
use Server::Starter qw(start_server restart_server stop_server); 
use File::Temp;
use Test::TCP;

plan tests => 2;

my $tmpfile = File::Temp->new(UNLINK => 1);

test_tcp(
   server => sub {
        my $port = shift;

        start_server(
            pid_file => $tmpfile->filename,
            daemonize => 1,
            port => $port,
            exec => [$^X, 't/11-stop-server.pl'],
        );
        exit 0;
    },
    client => sub {
        my $port = shift;

        while (!-s $tmpfile) {
            note 'pid file is not available';
            sleep 1; # wait pid file
        }

        my $pid = do {
            open my $fh, '<', $tmpfile
                or die "Cannot open $tmpfile: $!";
            local $/;
            <$fh>;
        };
        note "PID=$pid";
        is(kill(0, $pid), 1, 'there is a process');

        stop_server(
            pid_file => $tmpfile->filename,
            port => $port,
        );
        is(kill(0, $pid), 0, 'process was killed');
    },
);

