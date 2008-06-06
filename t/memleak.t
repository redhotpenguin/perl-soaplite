#!/usr/bin/perl
use Test::More;
use SOAP::Lite;
if (! eval { require Devel::Leak; }) {
    plan skip_all => 'Devel::Leak required for leak test';
    exit 0;
}

plan tests => 2;

=pod

=for developers

This test creates a SOAP::Lite and XMLRPC::Lite object, and calls a method
on it (which fails with a soap fault, as no endpoint is given).

Devel::Leak is used to check the number of SVs (that is, perl variables)
used in the perl interpreter before and after each call.

=cut

my $proxy = SOAP::Lite->new();
eval { $proxy->call('foo.bar', { foo => "barbaz" }); };
my $count = Devel::Leak::NoteSV($table);
eval { $proxy->call('foo.bar', { foo => "barbaz" }); };
ok $count >= Devel::Leak::NoteSV($table), 'number of SVs is constant or smaller from first to second call';

use XMLRPC::Lite;
my $xmlrpc = XMLRPC::Lite->new();
eval { $xmlrpc->call('foo.bar', { foo => "barbaz" }); };
my $count = Devel::Leak::NoteSV($table);
eval { $xmlrpc->call('foo.bar', { foo => "barbaz" }); };
ok $count >= Devel::Leak::NoteSV($table), 'number of SVs is constant or smaller from first to second call';
