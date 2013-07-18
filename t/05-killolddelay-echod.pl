#! /usr/bin/perl

use strict;
use warnings;

use lib qw(blib/lib lib);

use IO::Socket::INET;
use Server::Starter qw(server_ports);

my $sigfn = shift @ARGV;
open my $sigfh, '>', $sigfn
    or die "could not open file:$sigfn:$!";

$SIG{TERM} = $SIG{USR1} = sub {
    my $signame = shift;
    print $sigfh $signame;
    sleep 1;
    exit 0;
};

my $listener = IO::Socket::INET->new(
    Proto => 'tcp',
);
$listener->fdopen((values %{server_ports()})[0], 'w')
    or die "failed to bind listening socket:$!";

while (1) {
    if (my $conn = $listener->accept) {
        my $buf;
        while ($conn->sysread($buf, 1048576) > 0) {
            $conn->syswrite("$$:$buf");
        }
    }
}
