package SOAP::XMLSchema2001::Serializer;

use strict;
use vars qw(@EXPORT);

# no more warnings about "used only once"
*AUTOLOAD if 0;

*AUTOLOAD = \&SOAP::XMLSchema1999::Serializer::AUTOLOAD;

BEGIN {
  @EXPORT = qw(anyType anySimpleType float double decimal dateTime
               timePeriod gMonth gYearMonth gYear century
               gMonthDay gDay duration recurringDuration anyURI
               language integer nonPositiveInteger negativeInteger
               long int short byte nonNegativeInteger unsignedLong
               unsignedInt unsignedShort unsignedByte positiveInteger
               date time string hex base64 boolean
               QName
  );
  # Add QName to @EXPORT
  # predeclare subs, so ->can check will be positive
  foreach (@EXPORT) { eval "sub as_$_" }
}

sub nilValue { 'nil' }

sub anyTypeValue { 'anyType' }

sub as_long;        *as_long = \&SOAP::XMLSchema1999::Serializer::as_long;
sub as_float;       *as_float = \&SOAP::XMLSchema1999::Serializer::as_float;
sub as_string;      *as_string = \&SOAP::XMLSchema1999::Serializer::as_string;
sub as_anyURI;      *as_anyURI = \&SOAP::XMLSchema1999::Serializer::as_anyURI;

# TODO - QNames still don't work for 2001 schema!
sub as_QName;       *as_QName = \&SOAP::XMLSchema1999::Serializer::as_string;
sub as_hex;         *as_hex = \&as_hexBinary;
sub as_base64;      *as_base64 = \&as_base64Binary;
sub as_timeInstant; *as_timeInstant = \&as_dateTime;

# only 0 and 1 allowed - that's easy...
sub as_undef {
    $_[1]
    ? 'true'
    : 'false'
}

sub as_hexBinary {
    my ($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:hexBinary', %$attr},
        join '', map {
                uc sprintf "%02x", ord
            } split '', $value
    ];
}

sub as_base64Binary {
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
            'xsi:type' => 'xsd:base64Binary', %$attr
        },
        MIME::Base64::encode_base64($value,'')
    ];
}

sub as_boolean {
    my ($self, $value, $name, $type, $attr) = @_;
    # fix [ 1204279 ] Boolean serialization error
    return [
        $name,
        {
            'xsi:type' => 'xsd:boolean', %$attr
        },
        ( $value ne 'false' && $value )
            ? 'true'
            : 'false'
    ];
}

1;

__END__