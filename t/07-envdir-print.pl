#! /usr/bin/perl

use strict;
use warnings;

use lib qw(blib/lib lib);

use IO::Socket::INET;
use Server::Starter qw(server_ports);

$SIG{TERM} = $SIG{USR1} = sub {
    exit 0;
};

my $listener = IO::Socket::INET->new(
    Proto => 'tcp',
);
$listener->fdopen((values %{server_ports()})[0], 'w')
    or die "failed to bind listening socket:$!";

while (1) {
    if (my $conn = $listener->accept) {
        my $s = "";
        for my $envkey (keys %ENV) {
            $s .= $envkey . "=" . $ENV{$envkey} . "\n";
        }
        $conn->syswrite($s);
    }
}
