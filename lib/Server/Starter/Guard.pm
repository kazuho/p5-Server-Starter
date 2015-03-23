package Server::Starter::Guard;

use strict;
use warnings;

sub new {
    my ($klass, $handler) = @_;
    return bless [ $handler ], $klass;
}

sub DESTROY {
    my $self = shift;
    $self->[0]->();
}

1;
