use strict;
use warnings;
use lib '../lib';
use Test::More tests => 6; #qw(no_plan);
use Scalar::Util qw(blessed);
use_ok qw(SOAP::Lite::Custom::XML::Data);

my $data = SOAP::Lite::Custom::XML::Data->new();
ok blessed $data;

{
    no warnings qw(uninitialized);
    ok ! "$data", 'overloaded stringification';
}
undef $data;

ok $data = SOAP::Lite::Custom::XML::Data->new()
    ->value('1234');

# trigger autoloading on non-existant attribute
ok ! $data->foo();
my @result = $data->foo();
ok ! @result;
