use strict;
use warnings;
use Test::More tests => 2; #qw(no_plan);

use_ok qw(SOAP::Serializer);

my $obj = SOAP::Serializer->new();

is $obj->find_prefix('http://schemas.xmlsoap.org/soap/envelope/'), 'soap';
