use strict;
use warnings;
use Test::More;
use Server::Starter;

my $gotsig = 0;
Server::Starter::_set_sighandler('USR1', sub {
    warn "got SIGUSR1";
    ++$gotsig;
});

my $pid = fork;
die "fork failed:$!"
    unless defined $pid;
if ($pid == 0) {
    # child process, send signal twice
    sleep 1;
    kill 'USR1', getppid;
    sleep 1;
    kill 'USR1', getppid;
    sleep 10;
    die "child process not killed";
}

my @r = Server::Starter::_wait3(0);
ok ! @r, "nonblocking wait returns without pid";

for (my $i = 1; $i <= 2; ++$i) {
    @r = Server::Starter::_wait3(1);
    is $gotsig, $i, "woke up after signal (count: $i)";
    ok ! @r, "child is alive";
}

kill 'KILL', $pid;
@r = Server::Starter::_wait3(1);
is $gotsig, 2, "did not receive signal";
is $r[0], $pid, "child died";

done_testing;
