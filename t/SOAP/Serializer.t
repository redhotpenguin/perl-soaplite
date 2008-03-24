use strict;
use warnings;
use Test::More tests => 3; #qw(no_plan);

use_ok qw(SOAP::Serializer);

my $obj = SOAP::Serializer->new();

is $obj->find_prefix('http://schemas.xmlsoap.org/soap/envelope/'), 'soap';

like $obj->envelope('method' => SOAP::Data->name('test')),
    qr{ <test\s*/> }xms,
    'Empty method call does not use xsi:nil="true"';