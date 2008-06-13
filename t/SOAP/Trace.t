use strict;
use warnings;
use Test::More tests => 3; #qw(no_plan);
eval{ require Test::Warn; }
	or skip_all ('Cannot test without Test::Warn');
use_ok qw(SOAP::Trace);

SOAP::Trace->import('trace', '-debug');

test_warning();

SOAP::Trace->import('method' => sub { pass 'sub reference'});
SOAP::Trace::method('fault');


sub test_warning {
    Test::Warn::warning_like(
     sub { SOAP::Trace::trace('foo') },
     qr{: \s foo}x, 'is a warning'
 );
}