package Server::Starter::NS::PreFork;

use strict;
use warnings;

use Net::Server::PreFork;
use Net::Server::Proto::TCP;

use base qw(Net::Server::PreFork);

sub pre_bind {
    my $self = shift;
    my $prop = $self->{server};
    
    $self->fatal(
        "no environment variable SERVER_STARTER_PORT. Did you start the process"
            . " using server_starter?",
    ) unless $ENV{SERVER_STARTER_PORT};
    my %ports = map {
        +(split /=/, $_, 2)
    } split /;/, $ENV{SERVER_STARTER_PORT};
    
    for my $port (sort keys %ports) {
        my $sock = Net::Server::Proto::TCP->new();
        if ($port =~ /^(.*):(.*?)$/) {
            $sock->NS_host($1);
            $sock->NS_port($2);
        } else {
            $sock->NS_host('*');
            $sock->NS_port($port);
        }
        $sock->NS_proto('TCP');
        $sock->fdopen($ports{$port}, 'w')
            or $self->fatal("failed to map file descriptor:$ports{$port}:$!");
        push @{$prop->{sock}}, $sock;
    }
}

sub bind {
  my $self = shift;
  my $prop = $self->{server};
  
  ### if more than one port we'll need to select on it
  if( @{ $prop->{port} } > 1 || $prop->{multi_port} ){
    $prop->{multi_port} = 1;
    $prop->{select} = IO::Select->new();
    foreach ( @{ $prop->{sock} } ){
      $prop->{select}->add( $_ );
    }
  }else{
    $prop->{multi_port} = undef;
    $prop->{select}     = undef;
  }
}

sub sig_hup {
    my $self = shift;
    $self->log(
        0,
        $self->log_time(),
        "Server::Starter::NS::Prefork does not accept SIGHUP, send it to the"
            . " daemon!",
    );
}

1;
