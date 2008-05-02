=pod

=for developers

Cloneable is a test package for testing SOAP::Cloneable. It is just there
for inheriting from it.

=cut

package Cloneable;
use strict; use warnings;

use base qw(SOAP::Cloneable);

sub new {
    return bless { foo => 'bar' }, shift;
}


package main;
use lib '../lib';
use strict;
use warnings;
use Test::More tests => 3; #qw(no_plan);

my $cloneable = Cloneable->new();
ok my $clone = $cloneable->clone(), 'clone';
is $clone->{ foo }, 'bar', 'cloned value';

ok ! defined Cloneable->clone();

