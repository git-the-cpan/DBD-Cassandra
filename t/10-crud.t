use v5.14;
use Test::More;

unless ($ENV{CASSANDRA_HOST}) {
    plan skip_all => "CASSANDRA_HOST not set";
}

plan tests => 9;

use DBI;
my $dbh= DBI->connect("dbi:Cassandra:host=$ENV{CASSANDRA_HOST}", undef, undef, {RaiseError => 1, Warn => 1, PrintWarn => 0, PrintError => 0});
ok($dbh);

my $keyspace= "dbd_cassandra_tests";

ok(!eval {
    # Invalid: can't use prepared statements here
    $dbh->do('drop keyspace if exists ?', undef, $keyspace);
});

$dbh->do("drop keyspace if exists $keyspace");
$dbh->do("create keyspace $keyspace with replication={'class': 'SimpleStrategy', 'replication_factor': 1}");

ok(!eval {
    # Invalid: no keyspace selected yet
    $dbh->do("create table test_int (id bigint primary key)");
});

$dbh->do("use $keyspace");
$dbh->do("create table test_int (id bigint primary key)");

my $last_res;
for (1..5) {
    $last_res= $dbh->do("insert into test_int (id) values (?)", undef, $_);
}
is($last_res, '0E0');

for my $row (@{ $dbh->selectall_arrayref('select count(*) from test_int') }) {
    is($row->[0], 5);
}

ok(!eval {
    # Can't have a string in an integer
    $dbh->do("insert into test_int (id) values 'test'");
});

$dbh->do('delete from test_int where id in (?,?,3)', undef, 1, 2);
for my $row (@{ $dbh->selectall_arrayref('select count(*) from test_int') }) {
    is($row->[0], 2);
}

ok($dbh->do('insert into test_int (id) values (6)', { Consistency => 'any' }));
ok(!eval {
    # We have replication_factor=1, 'two' shouldn't work
    $dbh->do('insert into test_int (id) values (5)', { Consistency => 'two' });
});

$dbh->disconnect;
