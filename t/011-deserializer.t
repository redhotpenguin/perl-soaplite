use strict;
use warnings;
use Test;

use SOAP::Lite;

my $package = "SOAP::XMLSchemaSOAP1_1::Deserializer";

my @types11 = qw(
   ur_type anyURI 
   string float double decimal timeDuration recurringDuration uriReference 
   integer nonPositiveInteger negativeInteger long int short byte
   nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
   positiveInteger timeInstant time timePeriod date month year century 
   recurringDate recurringDay language
);

my @types12 = qw(
    anyType anyURI
    string float double decimal dateTime timePeriod gMonth gYearMonth gYear
    century gMonthDay gDay duration recurringDuration anyURI
    language integer nonPositiveInteger negativeInteger long int short byte
    nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
    positiveInteger date time dateTime
);

plan tests => scalar(@types11) + scalar(@types12) + (2 * 2) + 6;

test_deserializer('SOAP::XMLSchemaSOAP1_1::Deserializer', @types11);
test_deserializer('SOAP::XMLSchemaSOAP1_2::Deserializer', @types12);

sub test_deserializer {
    my $package = shift;
    my @types = @_;

    print "# $package\n";

    for my $type (@types) {
        my $method = "as_$type";
        ok $package->$method('test & <') eq 'test & <';
    }
    ok ! $package->as_boolean('false');
    ok $package->as_boolean('true');
}

ok (SOAP::XMLSchema1999::Deserializer->as_ur_type('Test') eq 'Test');
ok (SOAP::XMLSchema1999::Deserializer->as_undef(1) == 1);
ok (SOAP::XMLSchema1999::Deserializer->as_undef('true') == 1);
ok (SOAP::XMLSchema1999::Deserializer->as_undef(0) == 0);
ok (SOAP::XMLSchema1999::Deserializer->as_undef('false') == 0);

eval {SOAP::XMLSchema1999::Deserializer->as_undef('ZUMSL')};
ok $@;
undef $@;
