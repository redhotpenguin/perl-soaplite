use strict;
use warnings;
use Test;

use lib qw(lib);

use SOAP::Lite;
use SOAP::Data;

plan tests => 3;

ok my $soap = SOAP::Lite->new(
    proxy => 'loopback://test',
    # outputxml => 1,
);

ok my $som = $soap->call('test', SOAP::Data->name('test')->value(42));

ok $som->result() == 42;