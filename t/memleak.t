#!/usr/bin/perl
use Test::More;
use SOAP::Lite;
if (! eval { require Devel::Leak; }) {
	plan skip_all => 'Devel::Leak required for leak test';
	exit 0;
}

plan tests => 1;
eval { $proxy->call('foo.bar', { foo => "barbaz" }); };
my $count = Devel::Leak::NoteSV($table);
eval { $proxy->call('foo.bar', { foo => "barbaz" }); };
is $count, Devel::Leak::NoteSV($table), 'number of references is constant from first to second call';


