use strict;
use warnings;

use Test::More;
use SOAP::Lite;
use utf8;
use open ":encoding(utf-8)";

my $data = "mü\x{2013}";
my $serializer = SOAP::Serializer->new();

my $xml = $serializer->envelope( freeform => $data );
my ( $cycled ) = values %{ SOAP::Deserializer->deserialize( $xml )->body };
is( $data, $cycled, "UTF-8 string is the same after serializing" );


$data = "\x{FF}" x 256;
$xml = $serializer->envelope( freeform => $data );
( $cycled ) = values %{ SOAP::Deserializer->deserialize( $xml )->body };
is( $data, $cycled, "Binary data is the same after serializing" );


done_testing;
