package SOAP::Lite::Deserializer::XMLSchemaSOAP1_1;
use strict;

sub anyTypeValue { 'ur-type' }

sub as_boolean {
    shift;
    my $value = shift;
    return 1 if ($value eq '1' or $value eq 'true');
    return 0 if ($value eq '0' or $value eq 'false');
    die "Wrong boolean value '$value'\n"
}

sub as_base64 { shift; require MIME::Base64; MIME::Base64::decode_base64(shift) }

sub as_ur_type { $_[1] }

sub as_anyURI { $_[1] }

BEGIN {
    no strict 'refs';
    for my $method (qw(
        string float double decimal timeDuration recurringDuration uriReference
        integer nonPositiveInteger negativeInteger long int short byte
        nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
        positiveInteger timeInstant time timePeriod date month year century
        recurringDate recurringDay language
    )) { my $name = 'as_' . $method; *$name = sub { $_[1] } }
}

1;