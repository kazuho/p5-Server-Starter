# NAME

Server::Starter - a superdaemon for hot-deploying server programs

# SYNOPSIS

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

# DESCRIPTION

It is often a pain to write a server program that supports graceful restarts, with no resource leaks.  [Server::Starter](https://metacpan.org/pod/Server::Starter) solves the problem by splitting the task into two.  One is [start\_server](https://metacpan.org/pod/start_server), a script provided as a part of the module, which works as a superdaemon that binds to zero or more TCP ports or unix sockets, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming commenctions).  The spawned server programs under [Server::Starter](https://metacpan.org/pod/Server::Starter) call accept(2) and handle the requests.

To gracefully restart the server program, send SIGHUP to the superdaemon.  The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using [Server::Starter](https://metacpan.org/pod/Server::Starter) it is much easier to write a hot-deployable server.  Following are the only requirements a server program to be run under [Server::Starter](https://metacpan.org/pod/Server::Starter) should conform to:

\- receive file descriptors to listen to through an environment variable
\- perform a graceful shutdown when receiving SIGTERM

A Net::Server personality that can be run under [Server::Starter](https://metacpan.org/pod/Server::Starter) exists under the name [Net::Server::SS::PreFork](https://metacpan.org/pod/Net::Server::SS::PreFork).

# METHODS

- server\_ports

    Returns zero or more file descriptors on which the server program should call accept(2) in a hashref.  Each element of the hashref is: (host:port|port|path\_of\_unix\_socket) => file\_descriptor.

- start\_server

    Starts the superdaemon.  Used by the `start_server` script.

# AUTHOR

Kazuho Oku

# SEE ALSO

[Net::Server::SS::PreFork](https://metacpan.org/pod/Net::Server::SS::PreFork)

# LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
