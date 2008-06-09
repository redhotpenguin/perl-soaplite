package SOAP::XMLSchema1999::Serializer;

use strict;

use SOAP::Utils;

use vars qw(@EXPORT $AUTOLOAD);

sub AUTOLOAD {
    local($1,$2);
    my($package, $method) = $AUTOLOAD =~ m/(?:(.+)::)([^:]+)$/;
    return if $method eq 'DESTROY';
    no strict 'refs';

    my $export_var = $package . '::EXPORT';
    my @export = @$export_var;

# Removed in 0.69 - this is a total hack. For some reason this is failing
# despite not being a fatal error condition.
#  die "Type '$method' can't be found in a schema class '$package'\n"
#    unless $method =~ s/^as_// && grep {$_ eq $method} @{$export_var};

# This was added in its place - it is still a hack, but it performs the
# necessary substitution. It just does not die.
    if ($method =~ s/^as_// && grep {$_ eq $method} @{$export_var}) {
#      print STDERR "method is now '$method'\n";
    } else {
        return;
    }

    $method =~ s/_/-/; # fix ur-type

    *$AUTOLOAD = sub {
        my $self = shift;
        my($value, $name, $type, $attr) = @_;
        return [$name, {'xsi:type' => "xsd:$method", %$attr}, $value];
    };
    goto &$AUTOLOAD;
}

BEGIN {
    @EXPORT = qw(ur_type
        float double decimal timeDuration recurringDuration uriReference
        integer nonPositiveInteger negativeInteger long int short byte
        nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
        positiveInteger timeInstant time timePeriod date month year century
        recurringDate recurringDay language
        base64 hex string boolean
    );
    # TODO: replace by symbol table operations...
    # predeclare subs, so ->can check will be positive
    foreach (@EXPORT) { eval "sub as_$_" }
}

sub nilValue { 'null' }

sub anyTypeValue { 'ur-type' }

sub as_base64 {
    my ($self, $value, $name, $type, $attr) = @_;

    # Fixes #30271 for 5.8 and above.
    # Won't fix for 5.6 and below - perl can't handle unicode before
    # 5.8, and applying pack() to everything is just a slowdown.
    if (eval "require Encode; 1") {
        if (Encode::is_utf8($value)) {
            if (Encode->can('_utf8_off')) { # the quick way, but it may change in future Perl versions.
                Encode::_utf8_off($value);
            }
            else {
                $value = pack('C*',unpack('C*',$value)); # the slow but safe way,
                # but this fallback works always.
            }
        }
    }

    require MIME::Base64;
    return [
        $name,
        {
            'xsi:type' => SOAP::Utils::qualify($self->encprefix => 'base64'),
            %$attr
        },
        MIME::Base64::encode_base64($value,'')
    ];
}

sub as_hex {
    my ($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {
            'xsi:type' => 'xsd:hex', %$attr
        },
        join '', map {
            uc sprintf "%02x", ord
        } split '', $value
    ];
}

sub as_long {
    my($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:long', %$attr},
        $value
    ];
}

sub as_dateTime {
    my ($self, $value, $name, $type, $attr) = @_;
    return [$name, {'xsi:type' => 'xsd:dateTime', %$attr}, $value];
}

sub as_string {
    my ($self, $value, $name, $type, $attr) = @_;
    die "String value expected instead of @{[ref $value]} reference\n"
        if ref $value;
    return [
        $name,
        {'xsi:type' => 'xsd:string', %$attr},
        $value
    ];
}

sub as_anyURI {
    my($self, $value, $name, $type, $attr) = @_;
    die "String value expected instead of @{[ref $value]} reference\n" if ref $value;
    return [
        $name,
        {'xsi:type' => 'xsd:anyURI', %$attr},
        $value
    ];
}

sub as_undef { $_[1] ? '1' : '0' }

sub as_boolean {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    # fix [ 1204279 ] Boolean serialization error
    return [
        $name,
        {'xsi:type' => 'xsd:boolean', %$attr},
        ( $value ne 'false' && $value ) ? 'true' : 'false'
    ];
}

sub as_float {
    my($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:float', %$attr},
        $value
    ];
}

1;

__END__