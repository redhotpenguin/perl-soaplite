use strict;
use warnings;
use Test::More tests => 2;
use SOAP::Lite;

my ($opts, $soap);
my $proxy = 'http://services.soaplite.com/echo.cgi';
my $cafile = '/foo/bar';

$opts = [ SSL_ca_file => $cafile ];
$soap = SOAP::Lite->proxy ($proxy, ssl_opts => $opts);
is ($soap->transport->ssl_opts ('SSL_ca_file'), $cafile, "ssl_opts as arrayref is honoured");

$opts = { SSL_ca_file => $cafile };
$soap = SOAP::Lite->proxy ($proxy, ssl_opts => $opts);
TODO: {
	local $TODO = 'Arg to ssl_opts should be able to be hashref';
	is ($soap->transport->ssl_opts ('SSL_ca_file'), $cafile, "ssl_opts as hashref is honoured");
}
