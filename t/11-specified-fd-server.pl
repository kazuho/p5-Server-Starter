#! /usr/bin/perl
use strict;
use warnings;

use lib qw(blib/lib lib);

use IO::Socket::INET;
use Server::Starter qw(server_ports);

die "fd must be zero" unless ((values %{server_ports()})[0]) eq 0;

my $listener = IO::Socket::INET->new(
    Proto => 'tcp',
);
$listener->fdopen(0, 'w')
    or die "failed to bind listening socket:$!";

while (1) {
    if (my $conn = $listener->accept) {
        my $buf;
        while ($conn->sysread($buf, 1048576) > 0) {
            $conn->syswrite("$$:$buf");
        }
    }
}
