use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Posy-Plugin-InfoSQLite',
    license             => 'perl',
    dist_author         => 'Kathryn Andersen',
    dist_version_from   => 'lib/Posy/Plugin/InfoSQLite.pm',
	requires            => {
	'Posy' => 0.99,
	'Posy::Plugin::Info' => 0.05,
	'DBI' => 0,
	'DBD::SQLite' => 0,
	},
    build_requires => {
        'Test::More' => 0,
    },
);

$builder->create_build_script();
# create the Makefile.PL
use Module::Build::Compat;
print "creating Makefile.PL\n";
Module::Build::Compat->create_makefile_pl('passthrough', $builder);
