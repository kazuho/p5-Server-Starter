use strict;
use warnings;
use utf8;
use Test::More;
use Server::Starter qw(start_server stop_server);
use Server::Starter::Guard;
use File::Temp qw(tempdir);

plan tests => 1;

my $dir = tempdir( CLEANUP => 1 );
my $pidfile  = "$dir/pid";
my $sockfile = "$dir/server.sock";

fork_ok(
    child => sub {
        start_server(
            pid_file  => $pidfile,
            daemonize => 1,
            path      => $sockfile,
            exec      => [ $^X, qw(t/03-starter-unix-echod.pl) ],
        );
    },

    parent => sub {
        my $guard = Server::Starter::Guard->new(sub {
            stop_server( pid_file => $pidfile );
        });

        wait_for(sub { -e $pidfile })
            or BAIL_OUT("Pidfile '$pidfile' was not created in a timely fashion");

        wait_for(sub { -e $sockfile })
            or BAIL_OUT("Socket '$sockfile' was not created in a timely fashion");

        ok(-e $sockfile, 'there is a socket');
    },
) or die "fork failed: $!";

sub fork_ok {
    my (%args) = @_;

    my $pid = fork;
    return unless defined $pid;
    if ($pid == 0) {
        $args{child}->();
    }
    else {
        $args{parent}->($pid);
    }

    return 1;
}

sub wait_for {
    my ($code, %opts) = @_;

    my $times = $opts{times} || 10;
    my $every = $opts{every} || 1;

    while ( $times > 0 ) {
        return 1 if $code->();
        $times--;
        sleep $every;
    }

    return 0;
}
