use strict;
use warnings;
use Test::More;

use_ok("Server::Starter::Guard");

my $cnt = 0;

my $guard = Server::Starter::Guard->new(sub {
    $cnt++;
});

is $cnt, 0;
undef $guard;
is $cnt, 1;

done_testing;
