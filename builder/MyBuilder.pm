package builder::MyBuilder;
use strict;
use warnings;
use base qw(Module::Build);


# https://github.com/kazuho/p5-Server-Starter/issues/25
if (lc $^O eq "mswin32") {
    die "OS unsupported\n"; #will result in NA by cpantesters
}

1;

