# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

#use Test::More tests => 1;
#BEGIN { use_ok('POE::Component::Client::Ident') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my (@tests) = ( "not ok 2", "not ok 3" );

$|=1;
print "1..3\n";

use Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);
use POE::Component::Client::Ident;

POE::Component::Client::Ident->spawn ( 'Ident-Client' );

print "ok 1\n";

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

POE::Kernel->run();
exit;

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
}

sub server_stop {

  foreach ( @tests ) {
	print "$_\n";
  }

}

sub close_down_server {
  $_[KERNEL]->call ( 'Ident-Client' => 'shutdown' );
  delete $_[HEAP]->{server};
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
}

sub client_input {
    my ( $heap, $input, $wheel_id ) = @_[ HEAP, ARG0, ARG1 ];
     
    # Quick and dirty parsing as we know it is our component connecting
    my ($port1,$port2) = split ( /\s*,\s*/, $input );
    if ( $port1 == $heap->{Port1} and $port2 == $heap->{Port2} ) {
      $heap->{client}->{$wheel_id}->put( "$port1 , $port2 : USERID : UNIX : " . $heap->{UserID} );
      $tests[0] = "ok 2";
    } else {
      $heap->{client}->{$wheel_id}->put( "$port1 , $port2 : ERROR : UNKNOWN-ERROR");
    }
}

sub client_error {
    my ( $heap, $wheel_id ) = @_[ HEAP, ARG3 ];
    delete $heap->{client}->{$wheel_id};
}

sub server_error {
    delete $_[HEAP]->{server};
}

sub ident_client_reply {
  my ($kernel,$heap,$ref,$opsys,$userid) = @_[KERNEL,HEAP,ARG0,ARG1,ARG2];

  if ( $userid eq $heap->{UserID} ) {
    $tests[1] = "ok 3";
  }
  $kernel->delay( 'close_all' => undef );
  $kernel->yield( 'close_all' );
}

sub ident_client_error {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  $kernel->delay( 'close_all' => undef );
  $kernel->yield( 'close_all' );
}
