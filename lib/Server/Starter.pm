package Server::Starter;

use 5.008;
use strict;
use warnings;
use Carp;
use Fcntl;
use IO::Handle;
use IO::Socket::INET;
use IO::Socket::UNIX;
use List::MoreUtils qw(uniq);
use POSIX qw(:sys_wait_h);
use Proc::Wait3;
use Scope::Guard;

use Exporter qw(import);

our $VERSION = '0.11';
our @EXPORT_OK = qw(start_server restart_server server_ports);

my @signals_received;

sub start_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    $opts->{interval} = 1
        if not defined $opts->{interval};
    $opts->{signal_on_hup} ||= 'TERM';
    # normalize to the one that can be passed to kill
    $opts->{signal_on_hup} =~ tr/a-z/A-Z/;
    $opts->{signal_on_hup} =~ s/^SIG//i;
    
    # prepare args
    my $ports = $opts->{port};
    my $paths = $opts->{path};
    croak "either of ``port'' or ``path'' option is mandatory\n"
        unless $ports || $paths;
    $ports = [ $ports ]
        if ! ref $ports && defined $ports;
    $paths = [ $paths ]
        if ! ref $paths && defined $paths;
    croak "mandatory option ``exec'' is missing or is not an arrayref\n"
        unless $opts->{exec} && ref $opts->{exec} eq 'ARRAY';
    
    # open pid file
    my $pid_file_guard = sub {
        return unless $opts->{pid_file};
        open my $fh, '>', $opts->{pid_file}
            or die "failed to open file:$opts->{pid_file}: $!";
        print $fh "$$\n";
        close $fh;
        return Scope::Guard->new(
            sub {
                unlink $opts->{pid_file};
            },
        );
    }->();
    
    # open log file
    if ($opts->{log_file}) {
        open my $fh, '>>', $opts->{log_file}
            or die "failed to open log file:$opts->{log_file}: $!";
        STDOUT->flush;
        STDERR->flush;
        open STDOUT, '>&', $fh
            or die "failed to dup STDOUT to file: $!";
        open STDERR, '>&', $fh
            or die "failed to dup STDERR to file: $!";
        close $fh;
    }
    
    # create guard that removes the status file
    my $status_file_guard = $opts->{status_file} && Scope::Guard->new(
        sub {
            unlink $opts->{status_file};
        },
    );
    
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
    my $path_remove_guard = Scope::Guard->new(
        sub {
            -S $_ and unlink $_
                for @$paths;
        },
    );
    for my $path (@$paths) {
        if (-S $path) {
            warn "removing existing socket file:$path";
            unlink $path
                or die "failed to remove existing socket file:$path:$!";
        }
        unlink $path;
        my $sock = IO::Socket::UNIX->new(
            Listen => Socket::SOMAXCONN(),
            Local  => $path,
        ) or die "failed to listen to file $path:$!";
        fcntl($sock, F_SETFD, my $flags = '')
            or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$path=" . $sock->fileno;
        push @sock, $sock;
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    $ENV{SERVER_STARTER_GENERATION} = 0;
    
    # setup signal handlers
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP/);
    $SIG{PIPE} = 'IGNORE';
    
    # setup status monitor
    my ($current_worker, %old_workers);
    my $update_status = $opts->{status_file}
        ? sub {
            my $tmpfn = "$opts->{status_file}.$$";
            open my $tmpfh, '>', $tmpfn
                or die "failed to create temporary file:$tmpfn:$!";
            my %gen_pid = (
                ($current_worker
                 ? ($ENV{SERVER_STARTER_GENERATION} => $current_worker)
                 : ()),
                map { $old_workers{$_} => $_ } keys %old_workers,
            );
            print $tmpfh "$_:$gen_pid{$_}\n"
                for sort keys %gen_pid;
            close $tmpfh;
            rename $tmpfn, $opts->{status_file}
                or die "failed to rename $tmpfn to $opts->{status_file}:$!";
        } : sub {
        };
    
    # the main loop
    $current_worker = _start_worker($opts);
    $update_status->();
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
                $update_status->();
            }
        }
        for (; @signals_received; shift @signals_received) {
            if ($signals_received[0] eq 'HUP') {
                print STDERR "received HUP, spawning a new worker\n";
                $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
                $current_worker = _start_worker($opts);
                $update_status->();
                print STDERR "new worker is now running, sending $opts->{signal_on_hup} to old workers:";
                if (%old_workers) {
                    print STDERR join(',', sort keys %old_workers), "\n";
                } else {
                    print STDERR "none\n";
                }
                kill $opts->{signal_on_hup}, $_
                    for sort keys %old_workers;
            } else {
                goto CLEANUP;
            }
        }
    }
    
 CLEANUP:
    # cleanup
    $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
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
            $update_status->();
        }
    }
    
    print STDERR "exiting\n";
}

sub restart_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    die "--restart option requires --pid-file and --status-file to be set as well\n"
        unless $opts->{pid_file} && $opts->{status_file};
    
    # get pid
    my $pid = do {
        open my $fh, '<', $opts->{pid_file}
            or die "failed to open file:$opts->{pid_file}:$!";
        my $line = <$fh>;
        chomp $line;
        $line;
    };
    
    # function that returns a list of active generations in sorted order
    my $get_generations = sub {
        open my $fh, '<', $opts->{status_file}
            or die "failed to open file:$opts->{status_file}:$!";
        uniq sort { $a <=> $b } map { /^(\d+):/ ? ($1) : () } <$fh>;
    };
    
    # wait for this generation
    my $wait_for = do {
        my @gens = $get_generations->()
            or die "no active process found in the status file";
        pop(@gens) + 1;
    };
    
    # send HUP
    kill 'HUP', $pid
        or die "failed to send SIGHUP to the server process:$!";
    
    # wait for the generation
    while (1) {
        my @gens = $get_generations->();
        last if scalar(@gens) == 1 && $gens[0] == $wait_for;
        sleep 1;
    }
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
            my @args = @{$opts->{exec}};
            # child process
            { exec { $args[0] } @args };
            print STDERR "failed to exec $args[0]$!";
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

It is often a pain to write a server program that supports graceful restarts, with no resource leaks.  L<Server::Starter> solves the problem by splitting the task into two.  One is L<start_server>, a script provided as a part of the module, which works as a superdaemon that binds to zero or more TCP ports or unix sockets, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming commenctions).  The spawned server programs under L<Server::Starter> call accept(2) and handle the requests.

To gracefully restart the server program, send SIGHUP to the superdaemon.  The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using L<Server::Starter> it is much easier to write a hot-deployable server.  Following are the only requirements a server program to be run under L<Server::Starter> should conform to:

- receive file descriptors to listen to through an environment variable
- perform a graceful shutdown when receiving SIGTERM

A Net::Server personality that can be run under L<Server::Starter> exists under the name L<Net::Server::SS::PreFork>.

=head1 METHODS

=over 4

=item server_ports

Returns zero or more file descriptors on which the server program should call accept(2) in a hashref.  Each element of the hashref is: (host:port|port|path_of_unix_socket) => file_descriptor.

=item start_server

Starts the superdaemon.  Used by the C<start_server> script.

=back

=head1 AUTHOR

Kazuho Oku

=head1 SEE ALSO

L<Net::Server::SS::PreFork>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut