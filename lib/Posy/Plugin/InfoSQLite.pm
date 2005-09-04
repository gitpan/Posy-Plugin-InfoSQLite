package Posy::Plugin::InfoSQLite;
use strict;

=head1 NAME

Posy::Plugin::InfoSQLite - Posy plugin which gives supplementary entry information.

=head1 VERSION

This describes version B<0.01> of Posy::Plugin::InfoSQLite.

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
	Posy::Plugin::YamlConfig
	...
	Posy::Plugin::Info
	Posy::Plugin::InfoSQLite
	...);

=head1 DESCRIPTION

This plugin overrides the Posy::Plugin::Info plugin, giving the ".info"
information in an SQLite database rather than in .info files.
This will set
$info_* flavour variables which can be used in flavour templates. 

This plugin replaces the 'info' method for returning the info related
to an entry.
The other Posy::Plugin::Info functionality remains unchanged.

Note that if you were using the 'index_info' action for Posy::Plugin::Info,
it is best to remove it when using Posy::Plugin::InfoSQLite, since it
is now a redundant waste of time and space.

Note that it is entirely up to the user to populate and design the
SQLite database which is going to be used.  This plugin simply enables
the contents of one table (or view) of that database to be used
in Posy flavour templates.

This plugin expects (a) a database (b) a table (c) a column within that
table which has a value for each entry you want Info information on.
There are two ways which this can be done.  One is for the column
to contain a straight entry-id.  The other is for it to contain
a URL relative to the top of the site -- that is, basically like the
entry-id, but with a known extension like .html.  The second method
is useful if you want to use the database to be accessed separately
and still have useable URL data (for example, if you use a separate
search CGI script designed for SQLite databases).

=head2 Configuration

This expects configuration settings in the $self->{config} hash,
which, in the default Posy setup, can be defined in the main "config"
file in the data directory.

=over

=item B<infosqlite_db>

The location of the SQLite database file.

=item B<infosqlite_table>

The name of the table (or view) from which to get the info data.

=item B<infosqlite_entry_id_col>

The name of the column in the table which contains the file-id
of the entry file (see also L<infosqlite_url_col>).

=item B<infosqlite_url_col>

An alternative to B<infosqlite_entry_id_col>; this contains the name
of the column in the table which has the URL of the
entry file; basically, the same as the file-id, but with a proper
extension.

=back

=cut

use DBI;

=head1 OBJECT METHODS

Documentation for developers and those wishing to write plugins.

=head2 init

Do some initialization; make sure that default config values are set.

=cut
sub init {
    my $self = shift;
    $self->SUPER::init();

    # set defaults
    $self->{config}->{infosqlite_db} = ''
	if (!defined $self->{config}->{infosqlite_db});
    $self->{config}->{infosqlite_table} = ''
	if (!defined $self->{config}->{infosqlite_table});
    $self->{config}->{infosqlite_entry_id_col} = ''
	if (!defined $self->{config}->{infosqlite_entry_id_col});
    $self->{config}->{infosqlite_url_col} = ''
	if (!defined $self->{config}->{infosqlite_url_col});
} # init

=head1 Flow Action Methods

Methods implementing actions.  All such methods expect a
reference to a flow-state hash, and generally will update
either that hash or the object itself, or both in the course
of their running.

=head2 init_settings

Initialize at start.

=cut
sub init_settings {
    my $self = shift;
    $self->SUPER::init_settings();

    $self->{_infosqlite} = {};
    $self->{_infosqlite}->{dbh} = undef;
    $self->{_infosqlite}->{database} = undef;
} # init_settings

=head2 tidy_up

Tidy up at the end.

=cut
sub tidy_up {
    my $self = shift;
    $self->SUPER::tidy_up();

    if ($self->{_infosqlite}->{dbh})
    {
	$self->{_infosqlite}->{dbh}->disconnect();
	$self->{_infosqlite}->{dbh} = undef;
	$self->{_infosqlite}->{database} = undef;
    }
} # tidy_up

=head1 Helper Methods

Methods which can be called from within other methods.

=head2 info

    my %vars = $self->info($entry_id);

Gets the .info fields related to the given entry.

    my $val = $self->info($entry_id, field=>$name);

Get the value of the given .info field for this entry.

=cut
sub info {
    my $self = shift;
    my $entry_id = shift;
    my %args = (
	field=>undef,
	@_
    );
    my %info = ();
    # get the full info hash
    if (exists $self->{info}->{$entry_id}
	and defined $self->{info}->{$entry_id})
    {
	my $info_ref = $self->{info}->{$entry_id};
	%info = %{$info_ref};
    }
    elsif (!exists $self->{info}->{$entry_id})
    {
	%info = $self->read_info_from_db($entry_id);
	$self->{info}->{$entry_id} = (%info ? \%info : undef);
    }
    if ($args{field})
    {
	if (exists $info{$args{field}}
	    and defined $info{$args{field}})
	{
	    $self->debug(3, "info{$args{field}}: $info{$args{field}}");
	    return $info{$args{field}};
	}
    }
    else
    {
	return %info;
    }
    return undef;
} # info

=head2 read_info_from_db

    my %info = $self->read_info_from_db($entry_id);

Get the Info from the database.

=cut
sub read_info_from_db {
    my $self = shift;
    my $entry_id = shift;

    warn "read_info_from_db: $entry_id\n";
    $self->debug(2, "read_info_from_db: $entry_id");
    my $database = $self->{config}->{infosqlite_db};
    my $table = $self->{config}->{infosqlite_table};
    my $url_col = $self->{config}->{infosqlite_url_col};
    my $entry_id_col = $self->{config}->{infosqlite_entry_id_col};
    if ($database
	and ($url_col or $entry_id_col))
    {
	# connect
	my $dbh;
	if ($database eq $self->{_infosqlite}->{database})
	{
	    # already connected
	    $dbh = $self->{_infosqlite}->{dbh};
	}
	else
	{
	    if ($self->{_infosqlite}->{dbh})
	    {
		$self->{_infosqlite}->{dbh}->disconnect();
		$self->{_infosqlite}->{dbh} = undef;
		$self->{_infosqlite}->{database} = undef;
	    }
	    my $db_file = File::Spec->catfile($self->{data_dir}, $database);
	    if (!-r $db_file)
	    {
		$db_file = File::Spec->catfile($self->{config_dir}, $database);
		if (!-r $db_file)
		{
		    $db_file = File::Spec->catfile($self->{state_dir},
						   $database);
		    if (!-r $db_file)
		    {
			$db_file = $database;
			if (!-r $db_file)
			{
			    warn "cannot find database: $database";
			    return ();
			}
		    }
		}
	    }
	    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "");
	    if (!$dbh)
	    {
		warn "Can't connect to $database: $DBI::errstr";
		return ();
	    }
	    $self->{_infosqlite}->{dbh} = $dbh;
	    $self->{_infosqlite}->{database} = $database;
	}
	# make selection
	my $query = "SELECT * FROM $table ";
	if ($url_col)
	{
	    $query .= "WHERE $url_col GLOB '*$entry_id.*'";
	}
	elsif ($entry_id_col)
	{
	    $query .= "WHERE $entry_id_col = '$entry_id'";
	}
	my $sth = $dbh->prepare($query);
	if (!$sth)
	{
	    warn "Can't prepare query $query: $DBI::errstr";
	    return ();
	}
	my $rv = $sth->execute();
	if (!$rv)
	{
	    warn "Can't execute query $query: $DBI::errstr";
	    return ();
	}
	my $row_hash = $sth->fetchrow_hashref;

	if ($row_hash)
	{
	    return %{$row_hash};
	}
    }

    return ();
} # read_info_from_db

=head2 infosqlite_convert_value

    my $val = $obj->infosqlite_convert_value(value=>$val,
	format=>$format,
	name=>$name);

Convert a value according to the given formatting directive.

Directives are:

=over

=item upper

Convert to upper case.

=item lower

Convert to lower case.

=item int

Convert to integer

=item float

Convert to float.

=item string

Return the value with no change.

=item truncateI<num>

Truncate to I<num> length.

=item dollars

Return as a dollar value (float of precision 2)

=item percent

Show as if the value is a percentage.

=item title

Put any trailing ,The or ,A at the front (as this is a title)

=item comma_front

Put anything after the last comma at the front (as with an author name)

=item month

Convert the number value to a month name.

=item nth

Convert the number value to a N-th value.

=item url

Convert to a HTML href link.

=item email

Convert to a HTML mailto link.

=item hmail

Convert to a "humanized" version of the email, with the @ and '.'
replaced with "at" and "dot"

=item html

Convert to simple HTML (simple formatting)

=item proper

Convert to a Proper Noun.

=item wordsI<num>

Give the first I<num> words of the value.

=item alpha

Convert to a string containing only alphanumeric characters
(useful for anchors or filenames)

=item namedalpha

Similar to 'alpha', but prepends the 'name' of the value.
Assumes that the name is only alphanumeric.

=back

=cut
sub infosqlite_convert_value {
    my $self = shift;
    my %args = @_;
    my $value = $args{value};
    my $style = $args{format};
    my $name = $args{name};

    $value ||= '';
    ($_=$style) || ($_ = 'string');
    SWITCH: {
	/^upper/i &&     (return uc($value));
	/^lower/i &&     (return lc($value));
	/^int/i &&       (return (defined $value ? int($value) : 0));
	/^float/i &&     (return (defined $value && sprintf('%f',($value || 0))) || '');
	/^string/i &&    (return $value);
	/^trunc(?:ate)?(\d+)/ && (return substr(($value||''), 0, $1));
	/^dollars/i &&
	    (return (defined $value && length($value)
		     && sprintf('%.2f',($value || 0)) || ''));
	/^percent/i &&
	    (return (($value<0.2) &&
		     sprintf('%.1f%%',($value*100))
		     || sprintf('%d%%',int($value*100))));
	/^url/i &&    (return "<a href='$value'>$value</a>");
	/^email/i &&    (return "<a mailto='$value'>$value</a>");
	/^hmail/i && do {
	    $value =~ s/@/ at /;
	    $value =~ s/\./ dot /g;
	    return $value;
	};
	/^html/i &&	 (return $self->infosqlite_simple_html($value));
	/^title/i && do {
	    $value =~ s/(.*)[,;]\s*(A|The)$/$2 $1/;
	    return $value;
	};
	/^comma_front/i && do {
	    $value =~ s/(.*)[,]([^,]+)$/$2 $1/;
	    return $value;
	};
	/^proper/i && do {
	    $value =~ s/(^w|\b\w)/uc($1)/eg;
	    return $value;
	};
	/^month/i && do {
	    return $value if !$value;
	    return ($value == 1
		    ? 'January'
		    : ($value == 2
		       ? 'February'
		       : ($value == 3
			  ? 'March'
			  : ($value == 4
			     ? 'April'
			     : ($value == 5
				? 'May'
				: ($value == 6
				   ? 'June'
				   : ($value == 7
				      ? 'July'
				      : ($value == 8
					 ? 'August'
					 : ($value == 9
					    ? 'September'
					    : ($value == 10
					       ? 'October'
					       : ($value == 11
						  ? 'November'
						  : ($value == 12
						     ? 'December'
						     : $value
						    )
						 )
					      )
					   )
					)
				     )
				  )
			       )
			    )
			  )
			  )
	    );
	};
	/^nth/i && do {
	    return $value if !$value;
	    return ($value =~ /1$/
		? "${value}st"
		: ($value =~ /2$/
		    ? "${value}nd"
		    : ($value =~ /3$/
			? "${value}rd"
			: "${value}th"
		    )
		)
	    );
	};
	/^alpha/i && do {
	    $value =~ s/[^a-zA-Z0-9]//g;
	    return $value;
	};
	/^namedalpha/i && do {
	    $value =~ s/[^a-zA-Z0-9]//g;
	    $value = join('', $name, '_', $value);
	    return $value;
	};
	/^words(\d+)/ && do {
	    my $ct = $1;
	    ($ct>0) || return '';
	    my @sentence = split(/\s+/, $value);
	    my (@words) = splice(@sentence,0,$ct);
	    return join(' ', @words);
	};

	# otherwise, give up
	return "  {{{ style $style not supported }}}  ";
    }
} # infosqlite_convert_value

=head1 Private Methods

Methods which may or may not be here in future.

=head2 infosqlite_simple_html

$val = $obj->infosqlite_simple_html($val);

Do a simple HTML conversion of the value.
bold, italic, <br>

=cut
sub infosqlite_simple_html {
    my $self = shift;
    my $value = shift;

    $value =~ s#\n[\s][\s][\s]+#<br/>\n&nbsp;&nbsp;&nbsp;&nbsp;#sg;
    $value =~ s#\s*\n\s*\n#<br/><br/>\n#sg;
    $value =~ s#\*([^*]+)\*#<i>$1</i>#sg;
    $value =~ s/\^([^^]+)\^/<b>$1<\/b>/sg;
    $value =~ s/\#([^#]+)\#/<b>$1<\/b>/sg;
    $value =~ s/_([^_]+)_/<u>$1<\/u>/sg;
    return $value;
} # infosqlite_simple_html

=head1 INSTALLATION

Installation needs will vary depending on the particular setup a person
has.

=head2 Administrator, Automatic

If you are the administrator of the system, then the dead simple method of
installing the modules is to use the CPAN or CPANPLUS system.

    cpanp -i Posy::Plugin::InfoSQLite

This will install this plugin in the usual places where modules get
installed when one is using CPAN(PLUS).

=head2 Administrator, By Hand

If you are the administrator of the system, but don't wish to use the
CPAN(PLUS) method, then this is for you.  Take the *.tar.gz file
and untar it in a suitable directory.

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

=head2 User With Shell Access

If you are a user on a system, and don't have root/administrator access,
you need to install Posy somewhere other than the default place (since you
don't have access to it).  However, if you have shell access to the system,
then you can install it in your home directory.

Say your home directory is "/home/fred", and you want to install the
modules into a subdirectory called "perl".

Download the *.tar.gz file and untar it in a suitable directory.

    perl Build.PL --install_base /home/fred/perl
    ./Build
    ./Build test
    ./Build install

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules.

Therefore you will need to change the PERL5LIB variable to add
/home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}

=head1 REQUIRES

    Posy
    Posy::Core
    Posy::Plugin::Info

    Test::More

=head1 SEE ALSO

perl(1).
Posy
Posy::Plugin::Info
SQLite::Work

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2005 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Posy::Plugin::InfoSQLite
__END__
