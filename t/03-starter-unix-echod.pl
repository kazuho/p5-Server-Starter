#! /usr/bin/perl

use strict;
use warnings;

use lib qw(blib/lib lib);

use IO::Socket::UNIX;
use Server::Starter qw(server_ports);

my $listener = IO::Socket::UNIX->new()
    or die "failed to create unix socket:$!";
$listener->fdopen((values %{server_ports()})[0], 'w')
    or die "failde to bind to listening socket:$!";

while (1) {
    if (my $conn = $listener->accept) {
        while ($conn->sysread(my $buf, 1048576) > 0) {
            $conn->syswrite($buf);
        }
    }
}
