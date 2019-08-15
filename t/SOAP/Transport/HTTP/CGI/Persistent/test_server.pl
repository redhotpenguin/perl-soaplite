package main;

use strict;
use warnings;
use utf8;

use Encode;
use SOAP::Lite;
use SOAP::Transport::HTTP;

my $soap = SOAP::Transport::HTTP::CGI::Persistent->new(
    dispatch_to => 'main'
);

$soap->handle();

sub test {
    my ($self, $envelope) = @_;

    return SOAP::Data->name('testResult')->value(Encode::encode_utf8('Überall'))->type('string');
}

1;
