# Author: Chris "BinGOs" Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::Client::Ident::Agent;

use strict;
use POE qw( Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW
            Filter::Line Filter::Stream );
use POE::Filter::Ident;
use Carp;
use Socket;
use Sys::Hostname;
use vars qw($VERSION);

$VERSION = '0.1';

sub spawn {
    my ($package) = shift;
    my $sender = $poe_kernel->get_active_session;

    my ($peeraddr,$peerport,$sockaddr,$sockport,$identport) = _parse_arguments(@_);
 
    unless ( $peeraddr and $peerport and $sockaddr and $sockport ) {
        croak "Not enough arguments supplied to $package->spawn";
    }

    my $self = $package->new($sender,$peeraddr,$peerport,$sockaddr,$sockport,$identport);

    POE::Session->create(
        object_states => [
            $self => [qw(_start _sock_up _sock_down _sock_failed _parse_line _time_out shutdown)],
        ],
    );
}

sub new {
    my ( $package, $sender, $peeraddr, $peerport, $sockaddr, $sockport, $identport ) = @_;
    return bless { sender => $sender, event_prefix => 'ident_agent_', peeraddr => $peeraddr, peerport => $peerport, sockaddr => $sockaddr, sockport => $sockport, identport => $identport }, $package;
}

sub get_session {
  my ($self) = shift;

  return $self->{session};
}

sub _start {
    my ( $kernel, $self, $session ) = @_[ KERNEL, OBJECT, SESSION ];

    $self->{ident_filter} = POE::Filter::Ident->new();
    #$self->{ident_filter}->debug(1);
    $self->{session} = $session;
    $self->{socketfactory} = POE::Wheel::SocketFactory->new(
                                        SocketDomain => AF_INET,
                                        SocketType => SOCK_STREAM,
                                        SocketProtocol => 'tcp',
                                        RemoteAddress => $self->{'peeraddr'},
                                        RemotePort => ( $self->{'identport'} ? ( $self->{'identport'} ) : ( 113 ) ),
                                        SuccessEvent => '_sock_up',
                                        FailureEvent => '_sock_failed',
                                        ( $self->{sockaddr} ? (BindAddress => $self->{sockaddr}) : () ),
    );
    $self->{query_string} = $self->{peerport} . ", " . $self->{sockport};
    $self->{query} = { PeerAddr => $self->{peeraddr}, PeerPort => $self->{peerport}, SockAddr => $self->{sockaddr}, SockPort => $self->{sockport} };
}

sub _sock_up {
  my ($kernel,$self,$socket) = @_[KERNEL,OBJECT,ARG0];

  delete ( $self->{socketfactory} );

  $self->{socket} = new POE::Wheel::ReadWrite
  (
        Handle => $socket,
        Driver => POE::Driver::SysRW->new(),
        Filter => POE::Filter::Line->new( Literal => "\x0D\x0A" ),
        InputEvent => '_parse_line',
        ErrorEvent => '_sock_down',
  );

  unless ( $self->{socket} ) {
     $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
  }
  
  $self->{socket}->put($self->{query_string});
  $kernel->delay( '_time_out' => 30 );
}

sub _sock_down {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  unless ( $self->{had_a_response} ) {
    $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
  }
  delete ( $self->{socket} );
  $kernel->delay( '_time_out' => undef );
}


sub _sock_failed {
  my ($kernel, $self) = @_[KERNEL,OBJECT];

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
}

sub _time_out {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
  delete ( $self->{socket} );
}

sub _parse_line {
  my ($kernel,$self,$line) = @_[KERNEL,OBJECT,ARG0];
  my (@cooked);

  @cooked = @{$self->{ident_filter}->get( [$line] )};

  foreach my $ev (@cooked) {
    if ( $ev->{name} eq 'barf' ) {
	# Filter choked for whatever reason
        $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
    } else {
      $ev->{name} = $self->{event_prefix} . $ev->{name};
      my ($port1, $port2, @args) = @{$ev->{args}};
      if ( $self->_port_pair_matches( $port1, $port2 ) ) {
        $kernel->post( $self->{sender}, $ev->{name}, $self->{query}, @args );
      } else {
        $kernel->post( $self->{sender}, $self->{event_prefix} . 'error', $self->{query}, "UKNOWN-ERROR" );
      }
    }
  }
  $kernel->delay( '_time_out' => undef );
  $self->{had_a_response} = 1;
  delete ( $self->{socket} );
}

sub shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  
  $self->{had_a_response} = 1;
  delete ( $self->{socket} );
  $kernel->delay( '_time_out' => undef );
}

sub _port_pair_matches {
  my ($self) = shift;
  my ($port1,$port2) = @_;

  if ( $port1 == $self->{peerport} and $port2 == $self->{sockport} ) {
	return 1;
  }
  return 0;
}

sub _parse_arguments {
  my ( %hash ) = @_;
  my (@returns);

  # If we get a socket it takes precedence over any other arguments
  SWITCH: {
        if ( defined ( $hash{'IdentPort'} ) ) {
	  $returns[4] = $hash{'IdentPort'};
        }
	if ( defined ( $hash{'Socket'} ) ) {
	  $returns[0] = inet_ntoa( (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[1] );
    	  $returns[1] = (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[0];
	  $returns[2] = inet_ntoa( (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[1] );
          $returns[3] = (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[0];
	  last SWITCH;
	}
	if ( defined ( $hash{'PeerAddr'} ) and defined ( $hash{'PeerPort'} ) and defined ( $hash{'SockAddr'} ) and defined ( $hash{'SockAddr'} ) ) {
	  $returns[0] = $hash{'PeerAddr'};
    	  $returns[1] = $hash{'PeerPort'};
	  $returns[2] = $hash{'SockAddr'};
          $returns[3] = $hash{'SockPort'};
	  last SWITCH;
        }
  }
  return @returns;
}

=head1 NAME

POE::Component::Client::Ident::Agent - A component to provide a one-shot non-blocking Ident query.

=head1 SYNOPSIS

  use POE::Component::Client::Ident::Agent;

  POE::Component::Client::Ident::Agent->spawn( 
						PeerAddr => "192.168.1.12" # Originating IP Address
						PeerPort => 12345	   # Originating port
						SockAddr => "192.168.2.24" # Local IP address
						SockPort => 69 		   # Local Port
						Socket   => $socket_handle # Or pass in a socket handle
						IdentPort => 113	   # Port to send queries to on originator
									   # Default shown
						);

  sub _child {
   my ($action,$child,$reference) = @_[ARG0,ARG1,ARG2];

   if ( $action eq 'create' ) {
     # Stuff
   }
  }

  sub ident_agent_reply {
  }

  sub ident_agent_error {
  }

=head1 DESCRIPTION

POE::Component::Client::Ident::Agent is a POE component that provides a single "one shot" look up of a username
on the remote side of a TCP connection to other components and sessions, using the ident (auth/tap) protocol.
The Ident protocol is described in RFC 1413 L<http://www.faqs.org/rfcs/rfc1413.html>.

The component implements a single ident request. Your session spawns the component, passing the relevant arguments and at 
some future point will receive either a 'ident_agent_reply' or 'ident_agent_error', depending on the outcome of the query.

If you are looking for a robust method of managing Ident::Agent sessions then please consult the documentation for 
L<POE::Component::Client::Ident|POE::Component::Client::Ident>, which takes care of Agent management for you.

=head1 METHODS

=over

=item spawn

Takes either the arguments: PeerAddr, the remote IP address where a TCP connection has originated; PeerPort, the port
where the TCP has originated from; SockAddr, the address of our end of the connection; SockPort, the port of our end of 
the connection; OR: Socket, the socket handle of the connection, the component will work out all the details for you. If Socket is defined, it will override the settings of the other arguments, except for IdentPort, which is the port on the remote 
host where we send our ident queries. This is optional, defaults to 113.

There is no return value.

=back

=head1 OUTPUT

All the events returned by the component have a hashref as ARG0. This hashref contains the arguments that were passed to
the component. If a socket handle was passed, the hashref will contain the appropriate PeerAddr, PeerPort, SockAddr and SockPort.

The following events are sent to the calling session by the component:

=over

=item ident_agent_reply

Returned when the component receives a USERID response from the identd. ARG0 is hashref, ARG1 is the opsys field and ARG2 is 
the userid or something else depending on whether the opsys field is set to 'OTHER' ( Don't blame me, read the RFC ).

=item ident_agent_error

Returned when the component receives an ERROR response from the identd, there was some sort of communication error with the
remote host ( ie. no identd running ) or it had some other problem with making the connection to the other host. No matter. ARG0 is hashref, ARG1 is the type of error.

=item _child

Returned when the component starts. This is a good way of getting the session id of your component. See L<POE::Session|POE::Session> for more details, but if ARG0 eq 'create', then ARG2 will be a hashref as discussed above.

=back

=head1 AUTHOR

Chris Williams, E<lt>chris@bingosnet.co.uk<gt>

=head1 SEE ALSO

RFC 1413 L<http://www.faqs.org/rfcs/rfc1413.html>

L<POE::Session|POE::Session>

L<POE::Component::Client::Ident|POE::Component::Client::Ident>
