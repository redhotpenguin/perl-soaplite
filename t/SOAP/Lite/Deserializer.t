use strict;
use warnings;
use Test::More tests => 17; #qw(no_plan);
use Scalar::Util qw(refaddr);

use_ok qw(SOAP::Lite::Deserializer);

# test object creation and calling new as object method
ok my $deserializer = SOAP::Lite::Deserializer->new(), 'instantiate object';
is refaddr $deserializer, refaddr $deserializer->new(), 'return self if new called as object method';

# test is_xml (all variants)
ok $deserializer->is_xml('<Foo></Foo>'), '<Foo></Foo> is_xml';
ok $deserializer->is_xml('Fromme Schüler'), 'Fromme Schüler is_xml';
ok $deserializer->is_xml('My Header:'), 'My Header: is_xml';
ok ! $deserializer->is_xml('From martin'), 'From martin ! is_xml';
ok ! $deserializer->is_xml('X-Header: Foo'), 'X-Header: Foo ! is_xml';

# call typecast and check whether it returns undef
ok ! defined $deserializer->typecast(), 'typecast is undef';

# call baselocation with all variants of URIs, and without/with
# $deserializer->base();
baselocation: {
    my %uri = (
        'http://example.org/somewhere/over/the/rainbow' => 'http://example.org/somewhere/over/the/rainbow',
        'rainbow' => 'thismessage:/rainbow',
        q{} => q{},
    );

    for my $key ( keys %uri) {
        is $deserializer->baselocation($key), $uri{$key}, "$key baselocation";
    }
    $deserializer->base('foo:');
    is $deserializer->baselocation('rainbow'), 'foo:/rainbow', "rainbow baselocation (with base set)";
}

# deserialize messages without errors
ok my $som = $deserializer->deserialize( soap_message() ), 'deserialize SOAP message';

# MIME message
MIME: {
    # setup context
    my $soap = SOAP::Lite->new();
    $deserializer->context($soap);
    ok my $som = $deserializer->deserialize( mime_message() ), 'deserialize MIME message';
    $som->match('//theSignedForm');
}

# deserialize messages with errors
eval {
    my $som = $deserializer->deserialize( unresolved_attr_prefix() );
};
like $@, qr{\AUnresolved \s prefix \s'xsi'}x, 'error on unresolved attribute prefix';
eval {
    my $som = $deserializer->deserialize( unresolved_attr_value() );
};
like $@, qr{\A Unresolved \s prefix \s 'foo' \s for \s attribute \s value \s 'foo:value'}x
    , 'error on unresolved attribute value prefix';

sub soap_message {
    q{<SOAP-ENV:Envelope
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" >
    <SOAP-ENV:Body ><EnqueueMessage xmlns="http://www.example.org/MessageGateway2/"><MMessage>
                <MRecipientURI>mailto:test@example.com</MRecipientURI>
                <MMessageContent>TestContent for Message</MMessageContent>
    </MMessage></EnqueueMessage></SOAP-ENV:Body></SOAP-ENV:Envelope>};
}

sub unresolved_attr_prefix {
    q{<SOAP-ENV:Envelope
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" >
    <SOAP-ENV:Body ><EnqueueMessage xmlns="http://www.example.org/MessageGateway2/"><MMessage>
                <MRecipientURI xsi:type="foo:value">mailto:test@example.com</MRecipientURI>
    </MMessage></EnqueueMessage></SOAP-ENV:Body></SOAP-ENV:Envelope>};
}

sub unresolved_attr_value {
    q{<SOAP-ENV:Envelope
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" >
    <SOAP-ENV:Body ><EnqueueMessage xmlns="http://www.example.org/MessageGateway2/"><MMessage>
                <MRecipientURI xml:type="foo:value">mailto:test@example.com</MRecipientURI>
    </MMessage></EnqueueMessage></SOAP-ENV:Body></SOAP-ENV:Envelope>};
}

sub mime_message {
    q{Content-Type: Multipart/Related; boundary=MIME_boundary; type="text/xml"; start="<claim061400a.xml@claiming-it.com>"
SOAPAction: http://schemas.risky-stuff.com/Auto-Claim
Content-Description: This is the optional message description.

--MIME_boundary
Content-Type: text/xml; charset=UTF-8
Content-Transfer-Encoding: 8bit
Content-ID: <claim061400a.xml@claiming-it.com>

<?xml version='1.0' ?>
<SOAP-ENV:Envelope
  xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
    <claim:insurance_claim_auto id="insurance_claim_document_id"
      xmlns:claim="http://schemas.risky-stuff.com/Auto-Claim">
      <theSignedForm href="cid:claim061401a.tiff@claiming-it.com"/>
      <somexml href="cid:claim061403a.somexml@claiming-it.com"/>
      <!-- ... more claim details go here... -->
    </claim:insurance_claim_auto>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>

--MIME_boundary
Content-Type: image/tiff
Content-Transfer-Encoding: base64
Content-ID: <claim061401a.tiff@claiming-it.com>

AAECAyAgIAQFBg==
--MIME_boundary
Content-Type: text/plain
Content-Transfer-Encoding: binary
Content-ID: <claim061403a.somexml@claiming-it.com>

<a><b>c</b></a>
--MIME_boundary--};
}
