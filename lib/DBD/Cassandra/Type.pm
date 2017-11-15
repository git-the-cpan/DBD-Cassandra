package DBD::Cassandra::Type;
use v5.14;
use warnings;
use vars qw/@INPUT @OUTPUT/;

require Exporter;
our @ISA= 'Exporter';

my %lookup= (
    0  => [\&p2c_string, \&c2p_string,      'TYPE_CUSTOM'],
    1  => [\&p2c_string, \&c2p_string,      'TYPE_ASCII'],
    2  => [\&p2c_bigint, \&c2p_bigint,      'TYPE_BIGINT'],
    3  => [\&p2c_string, \&c2p_string,      'TYPE_BLOB'],
    4  => [\&p2c_bool,   \&c2p_bool,        'TYPE_BOOLEAN'],
    5  => [\&p2c_bigint, \&c2p_bigint,      'TYPE_COUNTER'],
    6  => [\&not_impl,   \&not_impl,        'TYPE_DECIMAL'],
    7  => [\&p2c_double, \&c2p_double,      'TYPE_DOUBLE'],
    8  => [\&p2c_float,  \&c2p_float,       'TYPE_FLOAT'],
    9  => [\&p2c_int,    \&c2p_int,         'TYPE_INT'],
    10 => [\&p2c_string, \&c2p_utf8string,  'TYPE_TEXT'],
    11 => [\&p2c_time,   \&c2p_time,        'TYPE_TIMESTAMP'],
    12 => [\&p2c_uuid,   \&c2p_uuid,        'TYPE_UUID'],
    13 => [\&p2c_string, \&c2p_utf8string,  'TYPE_VARCHAR'],
    14 => [\&not_impl,   \&not_impl,        'TYPE_VARINT'],
    15 => [\&p2c_uuid,   \&c2p_uuid,        'TYPE_TIMEUUID'],
    16 => [\&not_impl,   \&not_impl,        'TYPE_INET'],
);

sub not_impl { ... }
sub _pack {
    my ($p, $l, $m, $i)= @_;
    $m //= '';
    return "pack('l> $p', $l, (\$INPUT[$i] $m))";
}
sub _unpack {
    my ($p, $l, $m, $v)= @_;
    $m //= '';
    return "(unpack('$p', $v) $m)";
}

sub p2c_string {
    my ($i)= @_;
    return ("pack('l>/a', \$INPUT[$i])", "utf8::is_utf8(\$INPUT[$i]) && utf8::encode(\$INPUT[$i])");
}
sub c2p_string { return shift }
sub c2p_utf8string { my $var= shift; return ($var, "utf8::decode $var") }
sub p2c_bigint { return   _pack('q>', 8, undef, @_) }
sub c2p_bigint { return _unpack('q>', 8, undef, @_) }
sub p2c_time { return   _pack('q>', 8, undef, @_) }
sub c2p_time { return _unpack('q>', 8, undef, @_) }
sub p2c_int { return   _pack('l>', 4, undef, @_) }
sub c2p_int { return _unpack('l>', 4, undef, @_) }
sub p2c_bool { return   _pack('C', 1, ' ? 1 : 0', @_) }
sub c2p_bool { return _unpack('C', 1, undef, @_) }
sub p2c_float { return   _pack('f', 4, undef, @_) }
sub c2p_float { return _unpack('f', 4, undef, @_) }
sub p2c_double { return   _pack('d', 8, undef, @_) }
sub c2p_double { return _unpack('d', 8, undef, @_) }
sub p2c_uuid { return   _pack('H[32]', 16, ' =~ s/\W//rg', @_) }
sub c2p_uuid { return _unpack('H[32]', 16, ' =~ s/\A(\w{8})(\w{4})(\w{4})(\w{4})(\w{12})\z/$1-$2-$3-$4-$5/r', @_) }
#sub p2c_ { return   _pack('', , undef, @_) }
#sub c2p_ { return _unpack('', , undef, @_) }

our @EXPORT_OK= qw( build_row_encoder build_row_decoder );

sub build_row_encoder {
    my ($types)= @_;

    return sub{"\0\0"} unless @$types;

    my $count= 0+@$types;

    my $code= "my \$null= pack('l>', -1);\nmy \$length_bits= pack('n', $count);\nsub {\n    local *INPUT= \$_[0];\n";
    my $i= 0;

    my $result;
    for my $type (@$types) {
        if (ref $type) { $type= $type->{type}; }
        my $t= $lookup{$type} or die "Unknown type $type";
        my ($c, $prep)= $t->[0]($i);

        $code .= "    $prep if defined \$INPUT[$i];\n" if $prep;
        $result .= "        (defined \$INPUT[$i] ? ($c) : \$null) .\n";
        $i++;
    }
    $code = $code  . "    return\n        \$length_bits .\n" . substr($result, 0, -3). "\n    ;\n}";
    return eval($code);
}

sub build_row_decoder {
    my ($types)= @_;
    my $count= 0+@$types;

    # $_ = [count, body, dest_rows]
    my $code= "sub {\n    local *OUTPUT= \$_[2];\n    my (\$byte_count, \$tmp_val);\n    for my \$row_id (1..\$_[0]) {\n        my \@row;\n";

    my $i= 0;
    for my $type (@$types) {
        if (ref $type) { $type= $type->{type}; }
        my $t= $lookup{$type} or die "Unknown type $type";
        my ($c, $prep)= $t->[1]('$tmp_val');

        $code .= '        $byte_count= unpack("l>", substr $_[1], 0, 4, "");'."\n";
        $code .= '        if ($byte_count >= 0) {'."\n";
        $code .= '            $tmp_val= substr $_[1], 0, $byte_count, "";'."\n";
        $code .= '            '.$prep.';'."\n" if $prep;
        $code .= '            push @row, ('.$c.');'."\n";
        $code .= '        } else { push @row, undef; }'."\n";
        $i++;
    }

    $code .= "        push \@OUTPUT, \\\@row;\n    }\n}";
    return eval($code);
}

1;
