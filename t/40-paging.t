use v5.14;
use Test::More;

unless ($ENV{CASSANDRA_HOST}) {
    plan skip_all => "CASSANDRA_HOST not set";
}

plan tests => 101;

use DBI;
my $dbh= DBI->connect("dbi:Cassandra:host=$ENV{CASSANDRA_HOST}", undef, undef, {RaiseError => 1, Warn => 1, PrintWarn => 0, PrintError => 0});
ok($dbh);

my $keyspace= "dbd_cassandra_tests";

$dbh->do("drop keyspace if exists $keyspace");
$dbh->do("create keyspace $keyspace with replication={'class': 'SimpleStrategy', 'replication_factor': 1}");
$dbh->do("use $keyspace");
$dbh->do("create table test_int (id bigint primary key)");

for (1..50) {
    is($dbh->do("insert into test_int (id) values (?)", undef, $_), '0E0');
}

my %seen;
my $sth= $dbh->prepare('select * from test_int', { PerPage => 5 });
$sth->execute;
while (my $row= $sth->fetchrow_arrayref()) {
    $seen{$row->[0]}= 1;
}
for (1..50) {
    is($seen{$_}, 1);
}

$dbh->disconnect;
