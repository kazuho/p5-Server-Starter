package Server::Starter;

use strict;
use warnings;
use Carp;
use Fcntl;
use IO::Socket::INET;
use POSIX qw();
use Proc::Wait3;

use Exporter qw(import);

our @EXPORT_OK = qw(start_server server_ports);

sub start_server {
    my $opts = @_ == 1 ? shift : { @_ };
    
    # prepare args
    my $ports = $opts->{port}
        or croak "mandatory option ``port'' is missing\n";
    $ports = [ $ports ]
        unless ref $ports eq 'ARRAY';
    croak "``port'' should specify at least one port to listen to\n"
        unless @$ports;
    my $argv = $opts->{argv} || undef;
    croak "mandatory option ``argv'' is missing or is not an arrayref\n"
        unless ref $argv eq 'ARRAY';
    
    # start listening, setup envvar
    my @sock;
    my @sockenv;
    for my $port (@$ports) {
        my $sock;
        if ($port =~ /^\s*(\d+)\s*$/) {
            $sock = IO::Socket::INET->new(
                Listen    => Socket::SOMAXCONN(),
                LocalPort => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } elsif ($port =~ /^\s*(.*)\s*:\s*(\d+)\s*$/) {
            $port = "$1:$2";
            $sock = IO::Socket::INET->new(
                Listen    => Socket::SOMAXCONN(),
                LocalAddr => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } else {
            croak "invalid ``port'' value:$port\n"
        }
        fcntl($sock, F_SETFD, my $flags = '')
                or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$port=" . $sock->fileno;
        push @sock, $sock;
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    
    # setup signal handlers
    my @signals_received;
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP USR1 USR2/);
    $SIG{PIPE} = 'IGNORE';
    
    # the main loop
    my $current_worker = _start_worker($argv);
    my %old_workers;
    while (1) {
        my @r = wait3(1);
        if (@r) {
            my ($died_worker, $status) = @r;
            if ($died_worker == $current_worker) {
                print STDERR "worker process $died_worker died unexpectedly with status:$status, restarting\n";
                $current_worker = _start_worker($argv);
            } else {
                print STDERR "old worker process $died_worker died,"
                    . " status:$status\n";
                delete $old_workers{$died_worker};
            }
        }
        while (@signals_received) {
            my $signal_received = pop @signals_received;
            if ($signal_received eq 'HUP' || $signal_received eq 'USR1') {
                print STDERR "received HUP (or USR1), spawning a new worker\n";
                $old_workers{$current_worker} = 1;
                $current_worker = _start_worker($argv);
            } elsif ($signal_received eq 'USR2') {
                print STDERR "received USR2 indicating that the new worker is ready, sending TERM to old workers:";
                if (%old_workers) {
                    print join(',', sort keys %old_workers), "\n";
                } else {
                    print STDERR "none\n";
                }
                kill 'TERM', $_
                    for sort keys %old_workers;
            } else {
                goto CLEANUP;
            }
        }
    }
    
 CLEANUP:
    # cleanup
    $old_workers{$current_worker} = 1;
    undef $current_worker;
    print STDERR "received $signals_received[0], sending TERM to all workers:",
        join(',', sort keys %old_workers), "\n";
    kill 'TERM', $_
        for sort keys %old_workers;
    while (%old_workers) {
        if (my @r = wait3(1)) {
            my ($died_worker, $status) = @r;
            print STDERR "worker process $died_worker died, status:$status\n";
            delete $old_workers{$died_worker};
        }
    }
    
    print STDERR "exitting\n";
}

sub server_ports {
    die "no environment variable SERVER_STARTER_PORT. Did you start the process using server_starter?",
        unless $ENV{SERVER_STARTER_PORT};
    my %ports = map {
        +(split /=/, $_, 2)
    } split /;/, $ENV{SERVER_STARTER_PORT};
    \%ports;
}

sub _start_worker {
    my $argv = shift;
    my $pid = fork;
    die "fork(2) failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        # child process
        { exec(@$argv) };
        print STDERR "failed to exec  $argv->[0]:$!";
        exit(255);
    }
    print STDERR "starting new worker process, pid:$pid\n";
    sleep 1;
    $pid;
}

1;
