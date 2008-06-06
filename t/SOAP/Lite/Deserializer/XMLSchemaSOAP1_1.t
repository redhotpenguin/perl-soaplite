use Test::More tests => 40;
use strict;

use_ok qw(SOAP::Lite::Deserializer::XMLSchemaSOAP1_1);

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->anyTypeValue(),
    'ur-type',
    'anyTypeValue';

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_boolean('false'),
    0, 'as_boolean("false")';

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_boolean(0),
    0, 'as_boolean(0)';

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_boolean('true'),
    1, 'as_boolean("true")';

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_boolean(1),
    1, 'as_boolean(0)';


eval {
    SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_boolean('foo');
};
like $@, qr{\A Wrong \s boolean \s value}x;

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_ur_type('4242'),
    '4242', 'as_ur_type(4242)';

is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->as_base64('YWJj'), 'abc';

for (qw(
    string float double decimal timeDuration recurringDuration uriReference
    integer nonPositiveInteger negativeInteger long int short byte
    nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
    positiveInteger timeInstant time timePeriod date month year century
    recurringDate recurringDay language
    anyURI
    ) ) {

    no strict qw(refs);
    my $method = "as_$_";
    is SOAP::Lite::Deserializer::XMLSchemaSOAP1_1->$method('something nice'),
    'something nice', "$method('something nice')";

}