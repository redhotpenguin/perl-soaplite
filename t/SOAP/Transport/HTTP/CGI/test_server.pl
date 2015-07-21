package main;

use strict;
use warnings;

use SOAP::Lite;
use SOAP::Transport::HTTP;

my $soap = SOAP::Transport::HTTP::CGI->new(
    dispatch_to => 'main'
);

$soap->handle();

sub test {
    my ($self, $envelope) = @_;

use Encode;
#    return SOAP::Data->name('testResult')->value('Überall')->type('string');
    return SOAP::Data->name('testResult')->value(Encode::encode_utf('Überall'))->type('string');
}

1;