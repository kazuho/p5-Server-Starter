#! /usr/bin/perl

use strict;
use warnings;

use lib qw(blib/lib lib);
use IO::Socket::INET;
use Server::Starter qw(server_ports);

my $listener = IO::Socket::INET->new(
    Proto => 'udp',
);
$listener->fdopen((values %{server_ports()})[0], 'w')
    or die "failed to bind listening socket:$!";

$|= 1;
print "success\n";

sleep 100;
