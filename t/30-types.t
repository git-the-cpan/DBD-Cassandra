use v5.14;
use DBI;
use Test::More;
use utf8;

my $input= "__as__input";
my $warn= "__warn";

my $type_table= [
    # Type name, test input, test output (undef for error, $input for copying the input, $warn if we expect a perl warning)
    ['ascii',       'asd',  $input],
    ['ascii',       '∫∫',   undef],
    ['bigint',      5,      $input],
    ['bigint',      'asd',  $warn],
    ['blob',        'asd',  $input],
    ['boolean',     1,      $input],
    ['boolean',     0,      $input],
    ['boolean',     2,      1],
    ['boolean',     'asd',  1],
    ['double',      0.15,   $input],
    ['float',       0.2,    0.200000002980232], # Yeah.
    ['int',         5,      $input],
    ['text',        '∫∫',   $input],
    ['timestamp',   time(), $input],
    ['varchar',     '∫∫',   $input],
    ['uuid',        '34945442-c1d4-47db-bddd-5d2138b42cbc', $input],
    ['uuid',        'bad16', 'bad16000-0000-0000-0000-000000000000'],
    ['timeuuid',    '34945442-c1d4-47db-bddd-5d2138b42cbc', undef], # that's not a valid timeuuid
    ['timeuuid',    '568ef050-5aca-11e5-9c6b-eb15c19b7bc8', $input],
    ['timeuuid',    'bad16', undef],
];

unless ($ENV{CASSANDRA_HOST}) {
    plan skip_all => "CASSANDRA_HOST not set";
}

plan tests => 2+@$type_table;

my $dbh= DBI->connect("dbi:Cassandra:host=$ENV{CASSANDRA_HOST};keyspace=dbd_cassandra_tests", undef, undef, {RaiseError => 1});
ok($dbh);

for my $type (@$type_table) {
    my ($typename, $test_val, $output_val)= @$type;
    $dbh->do("create table if not exists test_type_$typename (id bigint primary key, test $typename)");
    my $random_id= sprintf '%.f', rand(10000);
    eval {
        my $did_warn;
        local $SIG{__WARN__}= sub { $did_warn= 1; };

        $dbh->do("insert into test_type_$typename (id, test) values (?, ?)", undef, $random_id, $test_val);
        my $row= $dbh->selectrow_arrayref("select test from test_type_$typename where id=$random_id", { async => 1 });
        if (!defined $output_val) {
            ok(0);
        } elsif ($output_val eq $warn) {
            ok($did_warn);
        } elsif ($output_val eq $input) {
            is($row->[0], $test_val, "input match $typename");
        } else {
            is($row->[0], $output_val, "perfect match $typename");
        }
        1;
    } or do {
        ok(!defined $output_val, "$typename raise error");
    };
}

# Counter needs special testing
COUNTER: {
    $dbh->do("create table if not exists test_type_counter (id bigint primary key, test counter)");
    my $random_id= sprintf '%.f', rand(10000);
    eval {
        $dbh->do("update test_type_counter set test=test+5 where id=?", undef, $random_id);
        my $row= $dbh->selectrow_arrayref("select test from test_type_counter where id=$random_id");
        ok($row->[0] == 5);
        1;
    } or do {
        ok(0);
    };
}

$dbh->disconnect;
