use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
			  'NAME'	=> 'POE::Component::Client::Ident',
			  'PREREQ_PM' => {
							  'warnings' => 0,
							  'POE'    => 0.06_07,
							  'Carp'   => 0,
							  'Socket' => 0,
							 },
			  'VERSION_FROM' => 'lib/POE/Component/Client/Ident.pm', # finds $VERSION
			  'dist' => { 'COMPRESS' => 'gzip --best' },
			 );
