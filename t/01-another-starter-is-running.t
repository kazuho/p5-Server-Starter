use strict;
use warnings;

use File::Temp ();
use Test::More tests => 3;

use Server::Starter qw(start_server);

my($pid_fh, $pid_filename) = File::Temp::tempfile(UNLINK => 1);
$pid_fh->autoflush;

# make non exists pid
my $old_pid = fork;
exit unless($old_pid);
waitpid($old_pid, 0);

ok(! kill(0, $old_pid), 'make sure old pid does not exists');
print $pid_fh $old_pid, "\n";

eval {
    start_server(path => '/dev/null', exec => [ '/dev/null' ], pid_file => $pid_filename);
};
like($@, qr/pid files exists/, 'pid files exists');

seek($pid_fh, 0, 0);
print $pid_fh $$, "\n";

eval {
    start_server(path => '/dev/null', exec => [ '/dev/null' ], pid_file => $pid_filename);
};
like($@, qr/another Server::Starter is running/, 'another Server::Starter is running');
