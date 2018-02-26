package Server::Starter;

use 5.008;
use strict;
use warnings;
use Carp;
use Fcntl;
use IO::Handle;
use IO::Socket::UNIX;
use POSIX qw(:sys_wait_h);
use Socket ();
use Server::Starter::Guard;
use Fcntl qw(:flock);

use Exporter qw(import);

our $VERSION = '0.34';
our @EXPORT_OK = qw(start_server restart_server stop_server server_ports);

my @signals_received;

sub start_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    $opts->{interval} = 1
        if not defined $opts->{interval};
    $opts->{signal_on_hup}  ||= 'TERM';
    $opts->{signal_on_term} ||= 'TERM';
    $opts->{backlog} ||= Socket::SOMAXCONN();
    for ($opts->{signal_on_hup}, $opts->{signal_on_term}) {
        # normalize to the one that can be passed to kill
        tr/a-z/A-Z/;
        s/^SIG//i;
    }

    # prepare args
    my $ports = $opts->{port};
    my $paths = $opts->{path};
    $ports = [ $ports ]
        if ! ref $ports && defined $ports;
    $paths = [ $paths ]
        if ! ref $paths && defined $paths;
    croak "mandatory option ``exec'' is missing or is not an arrayref\n"
        unless $opts->{exec} && ref $opts->{exec} eq 'ARRAY';

    # set envs
    $ENV{ENVDIR} = $opts->{envdir}
        if defined $opts->{envdir};
    $ENV{ENABLE_AUTO_RESTART} = $opts->{enable_auto_restart}
        if defined $opts->{enable_auto_restart};
    $ENV{KILL_OLD_DELAY} = $opts->{kill_old_delay}
        if defined $opts->{kill_old_delay};
    $ENV{AUTO_RESTART_INTERVAL} = $opts->{auto_restart_interval}
        if defined $opts->{auto_restart_interval};

    # open log file
    my $logfh;
    if ($opts->{log_file}) {
        if ($opts->{log_file} =~ /^\s*\|\s*/s) {
            my $cmd = $';
            open $logfh, '|-', $cmd
                or die "failed to open pipe:$opts->{log_file}: $!";
        } else {
            open $logfh, '>>', $opts->{log_file}
                or die "failed to open log file:$opts->{log_file}: $!";
        }
        $logfh->autoflush(1);
    }
    
    # create guard that removes the status file
    my $status_file_created;
    my $status_file_guard = $opts->{status_file} && Server::Starter::Guard->new(
        sub {
            if ($status_file_created) {
                unlink $opts->{status_file};
            }
        },
    );
    
    print STDERR "start_server (pid:$$) starting now...\n";
    
    # start listening, setup envvar
    my @sock;
    my @sockenv;
    for my $hostport (@$ports) {
        my ($domain, $sa);
        my $fd;
        my $sockopts = sub {};
        if ($hostport =~ /^\s*(\d+)(?:\s*=(\d+))?\s*$/) {
            # by default, only bind to IPv4 (for compatibility)
            $hostport = $1;
            $fd = $2;
            $domain = Socket::PF_INET;
            $sa = pack_sockaddr_in $1, Socket::inet_aton("0.0.0.0");
        } elsif ($hostport =~ /^\s*(?:\[\s*|)([^\]]*)\s*(?:\]\s*|):\s*(\d+)(?:\s*=(\d+))?\s*$/) {
            my ($host, $port) = ($1, $2);
            $fd = $3;
            if ($host =~ /:/) {
                # IPv6
                local $@;
                eval {
                    $hostport = "[$host]:$port";
                    my $addr = Socket::inet_pton(Socket::AF_INET6(), $host)
                        or die "failed to resolve host:$host:$!";
                    $sa = Socket::pack_sockaddr_in6($port, $addr);
                    $domain = Socket::PF_INET6();
                };
                if ($@) {
                    die "No support for IPv6. Please update Perl (or Perl modules)";
                }
                $sockopts = sub {
                    my $sock = shift;
                    local $@;
                    eval {
                        setsockopt $sock, Socket::IPPROTO_IPV6(), Socket::IPV6_V6ONLY(), 1;
                    };
                };
            } else {
                # IPv4
                $domain = Socket::PF_INET;
                $hostport = "$host:$port";
                my $addr = gethostbyname $host
                    or die "failed to resolve host:$host:$!";
                $sa = Socket::pack_sockaddr_in($port, $addr);
            }
        } else {
            croak "invalid ``port'' value:$hostport\n"
        }
        socket my $sock, $domain, Socket::SOCK_STREAM(), 0
            or die "failed to create socket:$!";
        setsockopt $sock, Socket::SOL_SOCKET, Socket::SO_REUSEADDR(), pack("l", 1);
        $sockopts->($sock);
        bind $sock, $sa
            or die "failed to bind to $hostport:$!";
        listen $sock, $opts->{backlog}
            or die "listen(2) failed:$!";
        fcntl($sock, F_SETFD, my $flags = '')
                or die "fcntl(F_SETFD, 0) failed:$!";
        if (defined $fd) {
            POSIX::dup2($sock->fileno, $fd)
                or die "dup2(2) failed(${fd}): $!";
            print STDERR "socket is duplicated to file descriptor ${fd}\n";
            close $sock;
            push @sockenv, "$hostport=$fd";
        } else {
            push @sockenv, "$hostport=" . $sock->fileno;
        }
        push @sock, $sock;
    }
    my $path_remove_guard = Server::Starter::Guard->new(
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
        my $saved_umask = umask(0);
        my $sock = IO::Socket::UNIX->new(
            Listen => $opts->{backlog},
            Local  => $path,
        ) or die "failed to listen to file $path:$!";
        umask($saved_umask);
        fcntl($sock, F_SETFD, my $flags = '')
            or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$path=" . $sock->fileno;
        push @sock, $sock;
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    $ENV{SERVER_STARTER_GENERATION} = 0;
    
    # setup signal handlers
    _set_sighandler($_, sub {
        push @signals_received, $_[0];
    }) for (qw/INT TERM HUP ALRM/);
    $SIG{PIPE} = 'IGNORE';
    
    # setup status monitor
    my ($current_worker, %old_workers, $last_restart_time);
    my $update_status = $opts->{status_file}
        ? sub {
            my $tmpfn = "$opts->{status_file}.$$";
            open my $tmpfh, '>', $tmpfn
                or die "failed to create temporary file:$tmpfn:$!";
            $status_file_created = 1;
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

    # now that setup is complete, redirect outputs to the log file (if specified)
    if ($logfh) {
        STDOUT->flush;
        STDERR->flush;
        open STDOUT, '>&=', $logfh
            or die "failed to dup STDOUT to file: $!";
        open STDERR, '>&=', $logfh
            or die "failed to dup STDERR to file: $!";
        close $logfh;
        undef $logfh;
    }

    # daemonize
    if ($opts->{daemonize}) {
        my $pid = fork;
        die "fork failed:$!"
            unless defined $pid;
        if ($pid != 0) {
            $path_remove_guard->dismiss;
            exit 0;
        }
        # in child process
        POSIX::setsid();
        $pid = fork;
        die "fork failed:$!"
            unless defined $pid;
        if ($pid != 0) {
            $path_remove_guard->dismiss;
            exit 0;
        }
        # do not close STDIN if `--port=n=0`.
        unless (grep /=0$/, @sockenv) {
            close STDIN;
            open STDIN, '<', '/dev/null'
                or die "reopen failed: $!";
        }
    }

    # open pid file
    my $pid_file_guard = sub {
        return unless $opts->{pid_file};
        open my $fh, '>', $opts->{pid_file}
            or die "failed to open file:$opts->{pid_file}: $!";
        flock($fh, LOCK_EX)
            or die "flock failed($opts->{pid_file}): $!";
        print $fh "$$\n";
        $fh->flush();
        return Server::Starter::Guard->new(
            sub {
                unlink $opts->{pid_file}
                    or warn "failed to unlink file:$opts->{pid_file}:$!";
                close $fh;
            },
        );
    }->();

    # setup the start_worker function
    my $start_worker = sub {
        my $pid;
        while (1) {
            $ENV{SERVER_STARTER_GENERATION}++;
            $pid = fork;
            die "fork(2) failed:$!"
                unless defined $pid;
            if ($pid == 0) {
                my @args = @{$opts->{exec}};
                # child process
                if (defined $opts->{dir}) {
                    chdir $opts->{dir} or die "failed to chdir:$opts->{dir}:$!";
                }
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
        # ready, update the environment
        $current_worker = $pid;
        $last_restart_time = time;
        $update_status->();
    };

    # setup the wait function
    my $wait = sub {
        my $block = @signals_received == 0;
        my @r;
        if ($block && $ENV{ENABLE_AUTO_RESTART}) {
            alarm(1);
            @r = _wait3($block);
            alarm(0);
        } else {
            @r = _wait3($block);
        }
        return @r;
    };

    # setup the cleanup function
    my $cleanup = sub {
        my $sig = shift;
        my $term_signal = $sig eq 'TERM' ? $opts->{signal_on_term} : 'TERM';
        $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
        undef $current_worker;
        print STDERR "received $sig, sending $term_signal to all workers:",
            join(',', sort keys %old_workers), "\n";
        kill $term_signal, $_
            for sort keys %old_workers;
        while (%old_workers) {
            if (my @r = _wait3(1)) {
                my ($died_worker, $status) = @r;
                print STDERR "worker $died_worker died, status:$status\n";
                delete $old_workers{$died_worker};
                $update_status->();
            }
        }
        print STDERR "exiting\n";
    };

    # the main loop
    $start_worker->();
    while (1) {
        # wait for next signal (or when auto-restart becomes necessary)
        my @r = $wait->();
        # reload env if necessary
        my %loaded_env = _reload_env();
        my @loaded_env_keys = keys %loaded_env;
        local @ENV{@loaded_env_keys} = map { $loaded_env{$_} } (@loaded_env_keys);
        $ENV{AUTO_RESTART_INTERVAL} ||= 360
            if $ENV{ENABLE_AUTO_RESTART};
        # restart if worker died
        if (@r) {
            my ($died_worker, $status) = @r;
            if ($died_worker == $current_worker) {
                print STDERR "worker $died_worker died unexpectedly with status:$status, restarting\n";
                $start_worker->();
            } else {
                print STDERR "old worker $died_worker died, status:$status\n";
                delete $old_workers{$died_worker};
                $update_status->();
            }
        }
        # handle signals
        my $restart;
        while (@signals_received) {
            my $sig = shift @signals_received;
            if ($sig eq 'HUP') {
                print STDERR "received HUP, spawning a new worker\n";
                $restart = 1;
                last;
            } elsif ($sig eq 'ALRM') {
                # skip
            } else {
                return $cleanup->($sig);
            }
        }
        if (! $restart && $ENV{ENABLE_AUTO_RESTART}) {
            my $auto_restart_interval = $ENV{AUTO_RESTART_INTERVAL};
            my $elapsed_since_restart = time - $last_restart_time;
            if ($elapsed_since_restart >= $auto_restart_interval && ! %old_workers) {
                print STDERR "autorestart triggered (interval=$auto_restart_interval)\n";
                $restart = 1;
            } elsif ($elapsed_since_restart >= $auto_restart_interval * 2) {
                print STDERR "autorestart triggered (forced, interval=$auto_restart_interval)\n";
                $restart = 1;
            }
        }
        # restart if requested
        if ($restart) {
            $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
            $start_worker->();
            print STDERR "new worker is now running, sending $opts->{signal_on_hup} to old workers:";
            if (%old_workers) {
                print STDERR join(',', sort keys %old_workers), "\n";
            } else {
                print STDERR "none\n";
            }
            my $kill_old_delay = defined $ENV{KILL_OLD_DELAY} ? $ENV{KILL_OLD_DELAY} : $ENV{ENABLE_AUTO_RESTART} ? 5 : 0;
            if ($kill_old_delay != 0) {
                print STDERR "sleeping $kill_old_delay secs before killing old workers\n";
                while ($kill_old_delay > 0) {
                    $kill_old_delay -= sleep $kill_old_delay || 1;
                }
            }
            print STDERR "killing old workers\n";
            kill $opts->{signal_on_hup}, $_
                for sort keys %old_workers;
        }
    }

    die "unreachable";
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
        my %gen;
        while (my $line = <$fh>) {
            if ($line =~ /^(\d+):/) {
                $gen{$1} = 1;
            }
        }
        sort { $a <=> $b } keys %gen;
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

sub stop_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    die "--stop option requires --pid-file to be set as well\n"
        unless $opts->{pid_file};

    # get pid
    open my $fh, '+<', $opts->{pid_file}
        or die "failed to open file:$opts->{pid_file}:$!";
    my $pid = do {
        my $line = <$fh>;
        chomp $line;
        $line;
    };

    print STDERR "stop_server (pid:$$) stopping now (pid:$pid)...\n";

    # send TERM
    kill 'TERM', $pid
        or die "failed to send SIGTERM to the server process:$!";

    # wait process
    flock($fh, LOCK_EX)
        or die "flock failed($opts->{pid_file}): $!";
    close $fh;
}

sub server_ports {
    die "no environment variable SERVER_STARTER_PORT. Did you start the process using server_starter?",
        unless defined $ENV{SERVER_STARTER_PORT};
    my %ports = map {
        +(split /=/, $_, 2)
    } split /;/, $ENV{SERVER_STARTER_PORT};
    \%ports;
}

sub _reload_env {
    my $dn = $ENV{ENVDIR};
    return if !defined $dn or !-d $dn;
    my $d;
    opendir($d, $dn) or return;
    my %env;
    while (my $n = readdir($d)) {
        next if $n =~ /^\./;
        open my $fh, '<', "$dn/$n" or next;
        chomp(my $v = <$fh>);
        $env{$n} = $v if defined $v;
    }
    return %env;
}

our $sighandler_should_die;
my $sighandler_got_sig;

sub _set_sighandler {
    my ($sig, $proc) = @_;
    $SIG{$sig} = sub {
        $proc->(@_);
        $sighandler_got_sig = 1;
        die "got signal"
            if $sighandler_should_die;
    };
}

sub _wait3 {
    my $block = shift;
    my $pid = -1;
    if ($block) {
        local $@;
        eval {
            $sighandler_got_sig = 0;
            local $sighandler_should_die = 1;
            die "exit from eval"
                if $sighandler_got_sig;
            $pid = wait();
        };
        if ($pid == -1 && $@) {
            $! = Errno::EINTR;
        }
    } else {
        $pid = waitpid(-1, WNOHANG);
    }
    return $pid > 0 ? ($pid, $?) : ();
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

It is often a pain to write a server program that supports graceful restarts, with no resource leaks.  L<Server::Starter> solves the problem by splitting the task into two.  One is L<start_server>, a script provided as a part of the module, which works as a superdaemon that binds to zero or more TCP ports or unix sockets, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming connections).  The spawned server programs under L<Server::Starter> call accept(2) and handle the requests.

To gracefully restart the server program, send SIGHUP to the superdaemon.  The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using L<Server::Starter> it is much easier to write a hot-deployable server.  Following are the only requirements a server program to be run under L<Server::Starter> should conform to:

=over 4

=item * receive file descriptors to listen to through an environment variable

=item * perform a graceful shutdown when receiving SIGTERM

=back

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
