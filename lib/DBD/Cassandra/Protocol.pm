package DBD::Cassandra::Protocol;
use v5.14;
use warnings;

require Exporter;
use Data::Dumper;

use DBD::Cassandra::Frame qw/recv_frame2 send_frame2/;

our (@EXPORT_OK, %EXPORT_TAGS);
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
    );

    @EXPORT_OK= (
        keys %constants,
        qw(
            recv_frame2
            send_frame2

            unpack_string_map
            pack_string_map
            unpack_longstring
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

    constant->import( { %constants } );
}

our @ISA= qw(Exporter);


sub unpack_string_map {
    ...
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

sub unpack_longstring { unpack('N/a', shift) }
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
    if ($id >= 0x20 && $id <= 0x22) { die "Unsupported type"; }
    my $custom;
    if ($id == 0) {
        $custom= unpack_string($_[0]);
    }
    return ($id, $custom);
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
            my ($type, $custom)= unpack_type($_[0]);

            push @columns, {
                keyspace => $keyspace // $global_keyspace,
                table => $table // $global_table,
                name => $name,
                type => $type,
                custom_type => $custom
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

    my $consistency= delete $params->{consistency} || 1;
    my $flags= 0;
    if ($params->{values}) {
        $flags |= 0x01;
    }

    my $body= pack('n C', $consistency, $flags);

    if ($flags & 1) {
        $body .= $params->{values};
    }

    return $body;
}

1;
