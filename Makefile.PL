use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
			  'NAME'	=> 'POE::Component::Client::Ident',
			  'PM'      => { 'Ident.pm' => '$(INST_LIBDIR)/Ident.pm',
					 'Ident-Agent.pm' => '$(INST_LIBDIR)/Ident/Agent.pm',
					 'Filter-Ident.pm' => '$(INST_LIBDIR)/../../Filter/Ident.pm',
				       },
			  'PREREQ_PM' => {
							  'POE'    => 0.06_07,
							  'Carp'   => 0,
							  'Socket' => 0,
							 },
			  'VERSION_FROM' => 'Ident.pm', # finds $VERSION
			  'dist' => { 'COMPRESS' => 'gzip --best' },
			 );
