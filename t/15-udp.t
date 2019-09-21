use strict;
use warnings;
use IO::Socket::INET;
use Net::EmptyPort qw(empty_port);
use Test::SharedFork;
use Test::More tests => 1;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

my $sockfile = File::Temp::tmpnam();

my $udp_port = empty_port({ proto => "udp" });
pipe my $readfh, my $writefh
    or die "pipe failed:$!";

my $pid = fork;
die "fork failed: $!"
    unless defined $pid;
if ($pid == 0) {
    # child
    open STDOUT, '>&', $writefh
        or die "failed to reopen STDOUT:$!";
    start_server(
        port => "u$udp_port",
        exec => [ $^X, qw(t/15-udp-server.pl) ],
    );
    exit 0;
} else {
    # parent
    while (my $line = <$readfh>) {
        last if $line =~ /^success/m;
    }
    pass "server up";
}

