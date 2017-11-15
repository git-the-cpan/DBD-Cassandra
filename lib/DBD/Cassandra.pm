package DBD::Cassandra;
use v5.14;
use warnings;

use DBD::Cassandra::dr;
use DBD::Cassandra::db;
use DBD::Cassandra::st;

our $VERSION= '0.04';
our $drh= undef;

sub driver {
    return $drh if $drh;

    my ($class, $attr)= @_;
    $drh = DBI::_new_drh($class."::dr", {
            'Name' => 'Cassandra',
            'Version' => $VERSION,
            'Attribution' => 'DBD::Cassandra by Tom van der Woerdt',
        }) or return undef;

    return $drh;
}

sub CLONE {
    undef $drh;
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

DBD::Cassandra - Database driver for Cassandra's CQL3

=head1 EXAMPLE

    use DBI;

    my $dbh = DBI->connect("dbi:Cassandra:host=localhost;keyspace=test", $user, $password);
    my $rows = $dbh->selectall_arrayref("SELECT id, field_one, field_two FROM some_table");

    for my $row (@$rows) {
        # Do something with your row
    }

    $dbh->disconnect;

=head1 DESCRIPTION

B<DBD::Cassandra> is a Perl5 Database Interface driver for Cassandra,
using the CQL3 query language.

=head2 Class Methods

=over

=item B<connect>

    use DBI;

    $dsn = "dbi:Cassandra:database=$database";
    $dsn = "dbi:Cassandra:keyspace=$keyspace;host=$hostname;port=$port";

=over

=item keyspace

=item database

=item db

Optionally, a keyspace to use by default. If this is not specified,
all queries must include the keyspace name.

=item hostname

Hostname to connect to. Defaults to C<localhost>

=item port

Port number to connect to. Defaults to C<3306>

=item compression

The compression method we should use for the connection. Currently
Cassandra allows C<lz4> and C<snappy>. We default to C<lz4>, which can
be disabled by setting C<compression=none>.

Only used for data frames longer than 512 bytes.

=item cql_version

There are several versions of the CQL language and this option lets you
pick one. Defaults to C<3.0.0>. Consult your Cassandra manual to see
which versions your database supports.

=back

=back

=head1 CAVEATS, BUGS, TODO

=over

=item *

There is currently no support for transactions. C<begin_work> will die
if you try to use it.

=item *

Thread support is untested. Use at your own risk.

=item *

Not all Cassandra data types are supported. These are currently
supported:

=over

=item * ascii

=item * bigint

=item * blob

=item * boolean

=item * custom

=item * double

=item * float

=item * int

=item * text

=item * varchar

=back

=item *

Cassandra/CQL3 is strict about the queries you write. When switching
from other databases, such as MySQL, this may come as a surprise. This
module supports C<quote(..)>, but try to use prepared statements
instead. They will save you a lot of trouble.

=back

=head1 LICENSE

This module is released under the same license as Perl itself.

=head1 AUTHORS

Tom van der Woerdt, L<tvdw@cpan.org|mailto:tvdw@cpan.org>
