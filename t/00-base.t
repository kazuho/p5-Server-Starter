use strict;
use warnings;

use Test::More tests => 2;

BEGIN {
    use_ok('Server::Starter');
    use_ok('Server::Starter::NS::Prefork');
}
