use Test::More qw(no_plan);
use SOAP::Lite::Schema::WSDL;

ok my $schema = SOAP::Lite::Schema::WSDL->new();

my $element = SOAP::Lite::Custom::XML::Data
        -> SOAP::Data::name('schema')
        -> set_value(
            SOAP::Lite::Custom::XML::Data
                -> SOAP::Data::name('complexType')
                ->attr({ name => 'test' })
);

my @result = SOAP::Lite::Schema::WSDL::parse_schema_element( $element );
is @result, 0, 'empty elements on empty complexType'

