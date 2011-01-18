use strict;
use warnings;

use File::Temp ();
use IO::Socket::UNIX;
use Test::More tests => 4;
use Test::SharedFork;

use Server::Starter qw(start_server);

$SIG{PIPE} = sub {};

my $sockfile = File::Temp::tmpnam();

my $pid = fork;
die "fork failed: $!"
    unless defined $pid;
if ($pid == 0) {
    # child
    start_server(
        path => $sockfile,
        exec => [ $^X, qw(t/03-starter-unix-echod.pl) ],
    );
    exit 0;
} else {
    # parent
    sleep 1
        until -e $sockfile;
    my $sock = IO::Socket::UNIX->new(
        Peer => $sockfile,
    ) or die "failed to connect to unix socket:$!";
    is $sock->syswrite('hello', 5), 5, 'write';
    is $sock->sysread(my $buf, 5), 5, 'read length';
    is $buf, 'hello', 'read data';
    kill 'TERM', $pid;
    while (wait != $pid) {}
    ok ! -e $sockfile, 'socket file removed after shutdown';
}

unlink $sockfile;
