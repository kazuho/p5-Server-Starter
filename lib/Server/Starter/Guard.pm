package Server::Starter::Guard;

use strict;
use warnings;

sub new {
    my ($klass, $handler) = @_;
    return bless {
       handler => $handler,
       active  => 1,
   }, $klass;
}

sub dismiss { shift->{active} = 0 }

sub DESTROY {
    my $self = shift;
    $self->{active} && $self->{handler}->();
}

1;
