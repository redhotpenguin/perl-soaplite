=pod

=for developers

Cloneable and NonCloneable are test packages for testing SOAP::Cloneable.

=cut

package Cloneable;
use strict; use warnings;

use base qw(SOAP::Cloneable);

sub new { return bless { foo => 'bar' }, shift; };

package NonCloneable;
use strict; use warnings;

sub new { return bless { foo => 'baz' }, shift; }

package main;
use lib '../lib';
use strict;
use warnings;
use Test::More tests => 6; #qw(no_plan);
use Scalar::Util qw(refaddr);

my $cloneable = Cloneable->new();
ok my $clone = $cloneable->clone(), 'clone';
is $clone->{ foo }, 'bar', 'cloned value';

ok ! defined Cloneable->clone();


my $deep_cloneable = Cloneable->new();
my $deep_noncloneable = NonCloneable->new();
my $deep_clone = Cloneable->new();
$deep_clone->{ foo } = $deep_cloneable;
$deep_clone->{ bar } = $deep_noncloneable;

$clone = $deep_clone->clone();

isnt refaddr($clone->{ foo }), refaddr($deep_cloneable), 'clone clonable child';
is refaddr($clone->{ bar }), refaddr($deep_noncloneable), 'copy nonclonable child';

ok ! defined SOAP::Cloneable::clone($deep_noncloneable), 'return undef on attempt to clone noncloneable';
