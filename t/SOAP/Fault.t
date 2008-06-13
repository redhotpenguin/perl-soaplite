use strict;
use warnings;
use Test::More tests => 9; #qw(no_plan);

use Scalar::Util qw(blessed refaddr);

use_ok qw(SOAP::Fault);

my $fault = SOAP::Fault->new();

is refaddr $fault, refaddr $fault->new();

ok $fault = SOAP::Fault->new(faultstring => 'foo',
    faultdetail => 'bar',
    faultcode => 'soap:server',
);

is $fault, "soap:server: foo";

$fault = SOAP::Fault::faultstring('bar');
ok blessed $fault, 'auto-create object on subroutine call';
is $fault->faultstring(), 'bar', 'faultstring';

{
    my $warning = q{};
    local $^W = 1;
    local $SIG{__WARN__} = sub { $warning = join q{}, @_ };

    $fault = SOAP::Fault->new('foo' => 'bar');
    is $warning, q{};

    $fault = SOAP::Fault->new('bar');
    like $warning , qr{\A Odd \s \(wrong\?\) \s number \s of \s parameters}x;

    $warning = q{};
    local $^W = 0;
    $fault = SOAP::Fault->new('bar');
    is $warning, q{};
}