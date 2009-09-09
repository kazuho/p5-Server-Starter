#! /usr/bin/perl

use strict;
use warnings;

use lib qw(blib/lib lib);

use IO::Socket::INET;
use Server::Starter qw(server_ports);

$SIG{TERM} = sub {
    exit 0;
};

my $gen = $ENV{SERVER_STARTER_GENERATION};

if ($gen == 1 || 3 <= $gen && $gen < 5) {
    # emulate startup failure
    exit 1;
}

my $listener = IO::Socket::INET->new(
    Proto => 'tcp',
);
$listener->fdopen((values %{server_ports()})[0], 'w')
    or die "failed to bind listening socket:$!";

while (1) {
    if (my $conn = $listener->accept) {
        $conn->syswrite($gen);
    }
}
