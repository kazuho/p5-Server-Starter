package Server::Starter;

use 5.008;
use strict;
use warnings;
use Carp;
use Fcntl;
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);
use Proc::Wait3;

use Exporter qw(import);

our $VERSION = '0.07';
our @EXPORT_OK = qw(start_server server_ports);

my @signals_received;

sub start_server {
    my $opts = @_ == 1 ? shift : { @_ };
    $opts->{interval} ||= 1;
    
    # prepare args
    my $ports = $opts->{port}
        or croak "mandatory option ``port'' is missing\n";
    $ports = [ $ports ]
        unless ref $ports eq 'ARRAY';
    croak "mandatory option ``exec'' is missing or is not an arrayref\n"
        unless $opts->{exec} && ref $opts->{exec} eq 'ARRAY';
    
    print STDERR "start_server (pid:$$) starting now...\n";
    
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
        die "failed to listen to $port:$!"
            unless $sock;
        fcntl($sock, F_SETFD, my $flags = '')
                or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$port=" . $sock->fileno;
        push @sock, $sock;
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    $ENV{SERVER_STARTER_GENERATION} = 0;
    
    # setup signal handlers
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP/);
    $SIG{PIPE} = 'IGNORE';
    
    # the main loop
    my $current_worker = _start_worker($opts);
    my %old_workers;
    while (1) {
        my @r = wait3(! scalar @signals_received);
        if (@r) {
            my ($died_worker, $status) = @r;
            if ($died_worker == $current_worker) {
                print STDERR "worker $died_worker died unexpectedly with status:$status, restarting\n";
                $current_worker = _start_worker($opts);
            } else {
                print STDERR "old worker $died_worker died, status:$status\n";
                delete $old_workers{$died_worker};
            }
        }
        for (; @signals_received; shift @signals_received) {
            if ($signals_received[0] eq 'HUP') {
                print STDERR "received HUP, spawning a new worker\n";
                $old_workers{$current_worker} = 1;
                $current_worker = _start_worker($opts);
                print STDERR "new worker is now running, sending TERM to old workers:";
                if (%old_workers) {
                    print STDERR join(',', sort keys %old_workers), "\n";
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
            print STDERR "worker $died_worker died, status:$status\n";
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
    my $opts = shift;
    my $pid;
    while (1) {
        $ENV{SERVER_STARTER_GENERATION}++;
        $pid = fork;
        die "fork(2) failed:$!"
            unless defined $pid;
        if ($pid == 0) {
            # child process
            { exec(@{$opts->{exec}}) };
            print STDERR "failed to exec $opts->{exec}->[0]:$!";
            exit(255);
        }
        print STDERR "starting new worker $pid\n";
        sleep $opts->{interval};
        if ((grep { $_ ne 'HUP' } @signals_received)
                || waitpid($pid, WNOHANG) <= 0) {
            last;
        }
        print STDERR "new worker $pid seems to have failed to start, exit status:$?\n";
    }
    $pid;
}

1;
__END__

=head1 NAME

Server::Starter - a superdaemon for hot-deploying server programs

=head1 SYNOPSIS

  # from command line
  % start_server --port=80 my_httpd

  # in my_httpd
  use Server::Starter qw(server_ports);

  my $listen_sock = IO::Socket::INET->new(
      Proto => 'tcp',
  );
  $listen_sock->fdopen((values %{server_ports()})[0], 'w')
      or die "failed to bind to listening socket:$!";

  while (1) {
      if (my $conn = $listen_sock->accept) {
          ....
      }
  }

=head1 DESCRIPTION

It is often a pain to write a server program that supports graceful restarts, with no resource leaks.  L<Server::Starter>, solves the problem by splitting the task into two.  One is L<start_server>, a script provided as a part of the module, which works as a superdaemon that binds to zero or more TCP ports, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming commenctions).  The spawned server programs under L<Server::Starter> call accept(2) and handle the requests.

The module can also be used to hot-deploy servers listening to unix domain sockets by omitting the --port option of L<start_server>.  In such case, the superdaemon will not bind to any TCP ports but instead concentrate on spawning the server program.

To gracefully restart the server program, send SIGHUP to the superdaemon.  The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using L<Server::Starter> it is much easier to write a hot-deployable server.  Following are the only requirements a server program to be run under L<Server::Starter> should conform to:

- receive file descriptors to listen to through an environment variable
- perform a graceful shutdown when receiving SIGTERM

A Net::Server personality that can be run under L<Server::Starter> exists under the name L<Net::Server::SS::PreFork>.

=head1 METHODS

=over 4

=item server_ports

Returns zero or more file descriptors on which the server program should call accept(2) in a hashref.  Each element of the hashref is: (host:port|port)=file_descriptor.

=item start_server

Starts the superdaemon.  Used by the C<start_server> scirpt.

=back

=head1 AUTHOR

Kazuho Oku E<lt>kazuhooku@gmail.comE<gt>
Copyright (C) 2009-2010 Cybozu Labs, Inc.

=head1 SEE ALSO

L<Net::Server::SS::PreFork>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
