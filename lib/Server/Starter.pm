package Server::Starter;

use strict;
use warnings;
use Carp;
use IO::Socket::INET;
use POSIX qw(dup);
use Proc::Wait3;

use Exporter qw(import);

our @EXPORT_OK = qw(start_server);

sub start_server {
    my $opts = shift;
    
    # prepare args
    my $ports = $opts->{port}
        or croak "mandatory option ``port'' is missing\n";
    $ports = [ $ports ]
        unless ref $ports eq 'ARRAY';
    croak "``port'' should specify at least one port to listen to\n";
    my $argv = $opts->{argv} || undef;
    croak "mandatory option ``argv'' is missing or is not an arrayref\n"
        unless ref $argv eq 'ARRAY';
    
    # start listening, setup envvar
    my @sockenv;
    for my $port (@$ports) {
        my $sock;
        if ($port =~ /^\s*(\d+)\s*$/) {
            $port = $1;
            $sock = IO::Socket::INET->new(
                LocalPort => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } elsif ($port =~ /^\s*(.*)\s*:\s*(\d+)\s*$/) {
            $port = "$1:$2";
            $sock = IO::Socket::INET->new(
                LocalAddr => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } else {
            croak "invalid ``port'' value:$port\n"
        }
        my $fd = dup($sock->fileno)
            or die "dup(2) failed:$!";
        push @sockenv, "$port=$fd";
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    
    # setup signal handlers
    my $signal_received;
    $SIG{TERM} = $SIG{HUP} = $SIG{USR1} = $SIG{USR2} = sub {
        $signal_received = $_[0];
    };
    
    # the main loop
    my $current_worker = _start_worker($argv);
    my %old_workers;
    while ($signal_received != 'TERM') {
        my @r = wait3(1);
        if (@r) {
            my ($died_worker, $status) = @r;
            if ($died_worker == $current_worker) {
                print "worker process $died_worker died unexpectedly with",
                    "status:$status, restarting\n";
                $current_worker = _start_worker($argv);
            } else {
                print "old worker process $died_worker died, status:$status\n";
                undef $old_workers{$died_worker};
            }
        }
        if ($signal_received == 'HUP' || $signal_received == 'USR1') {
            undef $signal_received;
            print "received HUP (or USR1), spawning a new worker\n";
            $old_workers{$current_worker} = 1;
            $current_worker = _start_worker($argv);
        } elsif ($signal_received == 'USR2') {
            undef $signal_received;
            if (%old_workers) {
                print "received USR2 indicating that the new worker is ready\n",
                    "sending TERM to old workers:";
                if (%old_workers) {
                    print join(',', sort keys %old_workers), "\n";
                } else {
                    print "no workers\n";
                }
                kill 'TERM', $_
                    for sort keys %old_workers;
            } else {
                print "received USR2\n";
            }
        }
    }
    
    # cleanup
    $old_workers{$current_worker} = 1;
    undef $current_worker;
    print "received TERM, sending TERM to all workers:",
        join(',', sort keys %old_workers), "\n";
    kill 'TERM', $_
        for sort keys %old_workers;
    while (%old_workers) {
        if (my @r = wait3(1)) {
            my ($died_worker, $status) = @r;
            print "worker process $died_worker died, status:$status\n";
            undef $old_workers{$died_worker};
        }
    }
    
    print "exitting\n";
}

sub _start_worker {
    my $argv = shift;
    my $pid = fork;
    die "fork(2) failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        # child process
        { exec(@$argv) };
        print "failed to exec  $argv->[0]:$!";
        exit(255);
    }
    print "started new worker process (pid=$pid)\n";
    sleep 1;
    $pid;
}

1;
