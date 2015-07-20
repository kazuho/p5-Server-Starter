use strict;
use warnings;
use Test::More;

use_ok("Server::Starter::Guard");

subtest "guard is called when it goes out of scope" => sub {
    my $cnt = 0;

    my $guard = Server::Starter::Guard->new(sub {
        $cnt++;
    });

    is $cnt, 0;
    undef $guard;
    is $cnt, 1;
};

subtest "guard can be dismissed" => sub {
    my $cnt = 0;

    my $guard = Server::Starter::Guard->new(sub {
        $cnt++;
    });

    $guard->dismiss;
    undef $guard;
    is $cnt, 0;
};

done_testing;
