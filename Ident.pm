# Author: Chris "BinGOs" Williams
#
# This module may be used, modified, and distributed under the same
# terms as Perl itself. Please see the license that came with your Perl
# distribution for details.
#

package POE::Component::Client::Ident;

use strict;
use POE;
use POE::Component::Client::Ident::Agent;
use Carp;
use vars qw($VERSION);

$VERSION = '0.4';

sub spawn {
    my ( $package, $alias ) = splice @_, 0, 2;

    unless ( $alias ) {
	croak "You must supply a kernel alias to $package->spawn";
    }

    my $self = $package->new( $alias );

    POE::Session->create (
	object_states => [ 
		$self => [qw(_start _child shutdown query ident_agent_reply ident_agent_error)],
        ],
    );
}

sub new {
  my ($package,$alias) = @_;

  return bless { Alias => $alias }, $package;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $kernel->alias_set( $self->{Alias} );
}

sub _child {
  my ($kernel,$self,$what,$child) = @_[KERNEL,OBJECT,ARG0,ARG1];

  if ( $what eq 'create' ) {
    # Stuff here to match up to our query
    my ($ref) = $_[ARG2];
    $self->{queries}->{ $ref->{SockAddr} }->{ $ref->{SockPort} }->{ $ref->{PeerAddr} }->{ $ref->{PeerPort} }->{Agent} = $child;
    $self->{children}->{$child} = 1;
  }
  if ( $what eq 'lose' ) {
    delete ( $self->{children}->{$child} );
  }
}

sub shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  # Stuff here to terminate currently running Agents
  foreach ( keys %{ $self->{children} } ) {
    $kernel->call( $_ => 'shutdown' );
  }

  $kernel->alias_remove ( $self->{Alias} );
}

sub query {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  my $package = ref $self;

  my ($peeraddr,$peerport,$sockaddr,$sockport,$socket) = _parse_arguments( @_[ARG0 .. $#_] );

  unless ( $peeraddr and $peerport and $sockaddr and $sockport ) {
    croak "Not enough arguments/items for $package->query";
  }

  $self->{queries}->{$sockaddr}->{$sockport}->{$peeraddr}->{$peerport}->{Requester} = $sender;

  POE::Component::Client::Ident::Agent->spawn( @_[ARG0 .. $#_] );
}

sub ident_agent_reply {
  my ($kernel,$self,$ref) = @_[KERNEL,OBJECT,ARG0];

  my ($requester) = $self->{queries}->{ $ref->{SockAddr} }->{ $ref->{SockPort} }->{ $ref->{PeerAddr} }->{ $ref->{PeerPort} }->{Requester};
  $kernel->post( $requester, 'ident_client_reply' , @_[ARG0 .. $#_] );
  
  # TODO: write a better harvest routine than this. Parse back up the list of refs and find empty ones.
  delete ( $self->{queries}->{ $ref->{SockAddr} }->{ $ref->{SockPort} }->{ $ref->{PeerAddr} }->{ $ref->{PeerPort} } );
}

sub ident_agent_error {
  my ($kernel,$self,$ref) = @_[KERNEL,OBJECT,ARG0];

  my ($requester) = $self->{queries}->{ $ref->{SockAddr} }->{ $ref->{SockPort} }->{ $ref->{PeerAddr} }->{ $ref->{PeerPort} }->{Requester};
  $kernel->post( $requester, 'ident_client_error' , @_[ARG0 .. $#_] );
  
  # TODO: write a better harvest routine than this. Parse back up the list of refs and find empty ones.
  delete ( $self->{queries}->{ $ref->{SockAddr} }->{ $ref->{SockPort} }->{ $ref->{PeerAddr} }->{ $ref->{PeerPort} } );
}

sub _parse_arguments {
  my ( %hash ) = @_;
  my (@returns);

  # If we get a socket it takes precedence over any other arguments
  SWITCH: {
        if ( defined ( $hash{'Socket'} ) ) {
          $returns[0] = inet_ntoa( (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[1] );
          $returns[1] = (unpack_sockaddr_in( getpeername $hash{'Socket'} ))[0];
          $returns[2] = inet_ntoa( (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[1] );
          $returns[3] = (unpack_sockaddr_in( getsockname $hash{'Socket'} ))[0];
          $returns[4] = $hash{'Socket'};
          last SWITCH;
        }
        if ( defined ( $hash{'PeerAddr'} ) and defined ( $hash{'PeerPort'} ) and defined ( $hash{'SockAddr'} ) and defined ( $
hash{'SockAddr'} ) ) {
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

POE::Component::Client::Ident - A component that provides non-blocking ident lookups to your sessions.

=head1 SYNOPSIS

   use POE::Component::Client::Ident;

   POE::Component::Client::Ident->spawn ( 'Ident-Client' );

   $kernel->post ( 'Ident-Client' => query => Socket => $socket );

   $kernel->post ( 'Ident-Client' => query => PeerAddr => '10.0.0.1', 
				              PeerPort => 2345,
					      SockAddr => '192.168.1.254',
					      SockPort => 6669,
					      BuggyIdentd => 1,
					      TimeOut => 30 );

=head1 DESCRIPTION

POE::Component::Client::Ident is a POE component that provides non-blocking Ident lookup services to
other components and sessions. The Ident protocol is described in RFC 1413 L<http://www.faqs.org/rfcs/rfc1413.html>.

The component takes requests in the form of events, spawns L<POE::Component::Client::Ident::Agent|POE::Component::Client::Ident::Agent> sessions to 
perform the Ident queries and returns the appropriate responses to the requesting session.

=head1 METHODS

=over

=item spawn

Takes one argument, a kernel alias to christen the new component with. Returns nothing.

=back

=head1 INPUT

The component accepts the following events:

=over

=item query

Takes either the arguments: PeerAddr, the remote IP address where a TCP connection has originated; PeerPort, the port
where the TCP has originated from; SockAddr, the address of our end of the connection; SockPort, the port of our end of
the connection; OR: Socket, the socket handle of the connection, the component will work out all the details for you. If Soc
ket is defined, it will override the settings of the other arguments. See the documentation for Ident-Agent for extra parameters you may pass.

=item shutdown

Takes no arguments. Causes the component to terminate gracefully. Any pending Ident::Agent components that are
running will be closed without returning events.

=back

=head1 OUTPUT

The events you can expect to receive having submitted a 'query'.

All the events returned by the component have a hashref as ARG0. This hashref contains the arguments that were passed to
the component. If a socket handle was passed, the hashref will contain the appropriate PeerAddr, PeerPort, SockAddr and Sock
Port.

=over

=item ident_client_reply

Returned when the component receives a USERID response from the identd. ARG0 is hashref, ARG1 is the opsys field and ARG2 is
the userid or something else depending on whether the opsys field is set to 'OTHER' ( Don't blame me, read the RFC ).

=item ident_client_error

Returned when the component receives an ERROR response from the identd, there was some sort of communication error with the
remote host ( ie. no identd running ) or it had some other problem with making the connection to the other host. No matter.
ARG0 is hashref, ARG1 is the type of error.

=back

=head1 AUTHOR

Chris Williams, E<lt>chris@bingosnet.co.uk<gt>

=head1 SEE ALSO

RFC 1413 L<http://www.faqs.org/rfcs/rfc1413.html>

L<POE::Component::Client::Ident::Agent|POE::Component::Client::Ident::Agent>
