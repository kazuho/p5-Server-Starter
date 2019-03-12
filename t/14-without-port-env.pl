#! /usr/bin/perl
use strict;
use warnings;

use lib qw(blib/lib lib);

use Server::Starter qw(server_ports);

my $fn = shift @ARGV;
open my $fh, '>', $fn
    or die "could not open file:$fn:$!";

my $env = $ENV{SERVER_STARTER_PORT};
my $server_ports = server_ports();
print $fh 'env: ' . (defined $env ? 'found' : 'not found') . "\n";
print $fh 'server_ports: ' . (%$server_ports ? 'not empty' : 'empty') . "\n";

$SIG{TERM} = $SIG{USR1} = sub {
    exit 0;
};


while (1) {
    sleep 1;
}
