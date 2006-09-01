use Test::More tests => 5;
BEGIN { use_ok('POE::Component::Client::Ident') };
diag( "Testing POE::Component::Client::Ident $POE::Component::Client::Ident::VERSION, POE $POE::VERSION, Perl $], $^X" );

use Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

my $self = POE::Component::Client::Ident->spawn ( 'Ident-Client' );

isa_ok( $self, 'POE::Component::Client::Ident' );

POE::Session->create
  ( inline_states =>
      { _start => \&server_start,
	_stop  => \&server_stop,
        server_accepted => \&server_accepted,
        server_error    => \&server_error,
        client_input    => \&client_input,
        client_error    => \&client_error,
	close_all	=> \&close_down_server,
	ident_client_reply => \&ident_client_reply,
	ident_client_error => \&ident_client_error,
      },
    heap => { Port1 => 12345, Port2 => 123, UserID => 'bingos' },
  );

$poe_kernel->run();
exit 0;

sub server_start {
    $_[HEAP]->{server} = POE::Wheel::SocketFactory->new
      ( 
	BindAddress => '127.0.0.1',
        SuccessEvent => "server_accepted",
        FailureEvent => "server_error",
      );

    ($our_port, undef) = unpack_sockaddr_in( $_[HEAP]->{server}->getsockname );
    $_[KERNEL]->post ( 'Ident-Client' => query => IdentPort => $our_port, PeerAddr => '127.0.0.1', PeerPort => $_[HEAP]->{Port1}, SockAddr => '127.0.0.1', SockPort => $_[HEAP]->{Port2} );

    $_[KERNEL]->delay ( 'close_all' => 60 );
    undef;
}

sub server_stop {
  pass("Server stop");
  undef;
}

sub close_down_server {
  $_[KERNEL]->call ( 'Ident-Client' => 'shutdown' );
  delete $_[HEAP]->{server};
  undef;
}

sub server_accepted {
    my $client_socket = $_[ARG0];

    my $wheel = POE::Wheel::ReadWrite->new
      ( Handle => $client_socket,
        InputEvent => "client_input",
        ErrorEvent => "client_error",
	Filter => POE::Filter::Line->new( Literal => "\x0D\x0A" ),
      );
    $_[HEAP]->{client}->{ $wheel->ID() } = $wheel;
    undef;
}

sub client_input {
    my ( $heap, $input, $wheel_id ) = @_[ HEAP, ARG0, ARG1 ];
     
    # Quick and dirty parsing as we know it is our component connecting
    my ($port1,$port2) = split ( /\s*,\s*/, $input );
    if ( $port1 == $heap->{Port1} and $port2 == $heap->{Port2} ) {
      $heap->{client}->{$wheel_id}->put( "$port1 , $port2 : USERID : UNIX : " . $heap->{UserID} );
      pass("Correct response from client");
    } else {
      $heap->{client}->{$wheel_id}->put( "$port1 , $port2 : ERROR : UNKNOWN-ERROR");
    }
    undef;
}

sub client_error {
    my ( $heap, $wheel_id ) = @_[ HEAP, ARG3 ];
    delete $heap->{client}->{$wheel_id};
    undef;
}

sub server_error {
    delete $_[HEAP]->{server};
    undef;
}

sub ident_client_reply {
  my ($kernel,$heap,$ref,$opsys,$userid) = @_[KERNEL,HEAP,ARG0,ARG1,ARG2];
  ok( $userid eq $heap->{UserID}, "USERID Test" );
  $kernel->delay( 'close_all' => undef );
  $kernel->yield( 'close_all' );
  undef;
}

sub ident_client_error {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->delay( 'close_all' => undef );
  $kernel->yield( 'close_all' );
  undef;
}
