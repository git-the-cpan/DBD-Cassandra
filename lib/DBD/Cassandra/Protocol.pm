package DBD::Cassandra::Protocol;
use v5.14;
use warnings;

require Exporter;
our @ISA= qw(Exporter);

use constant;

our (@EXPORT_OK, %EXPORT_TAGS);
my (%consistency_lookup);
BEGIN {
    my %constants= (
        OPCODE_ERROR => 0,
        OPCODE_STARTUP => 1,
        OPCODE_READY => 2,
        OPCODE_AUTHENTICATE => 3,
        OPCODE_OPTIONS => 5,
        OPCODE_SUPPORTED => 6,
        OPCODE_QUERY => 7,
        OPCODE_RESULT => 8,
        OPCODE_PREPARE => 9,
        OPCODE_EXECUTE => 10,
        OPCODE_REGISTER => 11,
        OPCODE_EVENT => 12,
        OPCODE_BATCH => 13,
        OPCODE_AUTH_CHALLENGE => 14,
        OPCODE_AUTH_RESPONSE => 15,
        OPCODE_AUTH_SUCCESS => 16,

        RESULT_VOID => 1,
        RESULT_ROWS => 2,
        RESULT_SET_KEYSPACE => 3,
        RESULT_PREPARED => 4,
        RESULT_SCHEMA_CHANGE => 5,

        CONSISTENCY_ANY => 0,
        CONSISTENCY_ONE => 1,
        CONSISTENCY_TWO => 2,
        CONSISTENCY_THREE => 3,
        CONSISTENCY_QUORUM => 4,
        CONSISTENCY_ALL => 5,
        CONSISTENCY_LOCAL_QUORUM => 6,
        CONSISTENCY_EACH_QUORUM => 7,
        CONSISTENCY_SERIAL => 8,
        CONSISTENCY_LOCAL_SERIAL => 9,
        CONSISTENCY_LOCAL_ONE => 10,
    );

    @EXPORT_OK= (
        keys %constants,
        qw(
            pack_string_map
            unpack_string_multimap
            pack_longstring
            unpack_shortbytes
            pack_shortbytes
            unpack_bytes
            pack_bytes
            unpack_string

            unpack_metadata
            unpack_type

            pack_parameters
        )
    );

    %EXPORT_TAGS= (
        constants => [ keys %constants ],
        all => [ @EXPORT_OK ]
    );

    %consistency_lookup= map {
        my $key= $_;
        $key =~ s/CONSISTENCY_//;
        (lc $key) => $constants{$_}
    } keys %constants;

    constant->import( { %constants } );
}

sub unpack_string_multimap {
    my $result= {};
    my $count= unpack('n', substr $_[0], 0, 2, '');
    for (1..$count) {
        my $key= unpack_string($_[0]);
        my $valcount= unpack('n', substr $_[0], 0, 2, '');
        my $values= [];
        for (1..$valcount) {
            push @$values, unpack_string($_[0]);
        }
        $result->{$key}= $values;
    }
    return $result;
}

sub pack_string_map {
    my $hash= shift;
    my $body= '';
    my $count= 0;
    keys %$hash; while (my ($key, $value)= each %$hash) {
        $body .= pack('n/an/a', $key, $value);
        $count++;
    }
    return pack('n', $count).$body;
}

sub pack_longstring { pack('N/a', shift) }

sub unpack_shortbytes {
    my ($len)= unpack('n', substr $_[0], 0, 2, '');
    return '' if $len == 0;
    return substr $_[0], 0, $len, '';
}

sub pack_shortbytes { pack('n/a', shift) }

sub unpack_bytes {
    my ($len)= unpack('l>', substr $_[0], 0, 4, '');
    return '' if $len == 0;
    return undef if $len < 0;
    return substr $_[0], 0, $len, '';
}

sub pack_bytes { !defined $_[0] ? pack('l>', -1) : (pack('l>', length($_[0])).$_[0]) }

sub unpack_string {
    return unpack_shortbytes @_;
}

sub unpack_type {
    my ($id)= unpack('n', substr $_[0], 0, 2, '');
    my $detailed_type;
    if ($id == 0) {
        $detailed_type= unpack_string($_[0]);
    } elsif ($id >= 0x20 && $id <= 0x22) {
        $detailed_type= unpack_type($_[0]);
    } elsif ($id > 0x20) {
        die 'Not supported';
    }
    return [$id, $detailed_type];
}

sub unpack_metadata {
    # Sorry: we'll be using $_[0] a lot

    my ($flags, $columns_count)= unpack('NN', substr $_[0], 0, 8, '');
    my ($paging_state, $global_keyspace, $global_table, @columns);

    if ($flags & 2) {
        $paging_state= unpack_bytes($_[0]);
    }
    if ($flags & 1) {
        ($global_keyspace, $global_table)= ( unpack_string($_[0]), unpack_string($_[0]) );
    }
    if (! ($flags & 4)) {
        for (1..$columns_count) {
            my ($keyspace, $table);
            if (! $flags & 1) {
                ($keyspace, $table)= (unpack_string($_[0]), unpack_string($_[0]));
            }
            my $name= unpack_string($_[0]);
            my $type= unpack_type($_[0]);

            push @columns, {
                keyspace => $keyspace // $global_keyspace,
                table => $table // $global_table,
                name => $name,
                type => $type,
            };
        }
    }

    return {
        paging_state => $paging_state,
        columns => \@columns,
    };
}

sub pack_parameters {
    my ($params)= @_;

    my $consistency= $params->{consistency};
    if (defined(my $c= $consistency_lookup{lc $consistency})) {
        $consistency= $c;
    } elsif ($consistency !~ m/\A[0-9]+\z/) {
        die "Unknown consistency argument: $consistency";
    }

    my ($prepare_id, $values, $result_page_size, $paging_state)=
        @$params{'prepare_id', 'values', 'result_page_size', 'paging_state'};

    my $flags= ($values ? 0x01 : 0) | ($result_page_size ? 0x04 : 0) | ($paging_state ? 0x08 : 0);

    my $body= pack('n/a n C', $prepare_id, $consistency, $flags);

    $body .= $values if $values;
    $body .= pack('N', $result_page_size) if $result_page_size;
    $body .= pack_bytes($paging_state) if $paging_state;

    return $body;
}

1;
