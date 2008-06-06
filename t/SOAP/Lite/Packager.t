use strict;
use warnings;
use Test::More tests => 7; #qw(no_plan);
use Scalar::Util qw(blessed);
use_ok qw(SOAP::Lite::Packager);

ok SOAP::Lite::Packager->new(), 'SOAP::Lite::Packager->new()';
ok my $mime = SOAP::Lite::Packager::MIME->new(), 'SOAP::Lite::Packager::MIME->new()';

my $entity = bless {}, 'MIME::Entity';
ok $mime->is_supported_part($entity), 'MIME::Entity is supported';


my $mp = SOAP::Lite::Packager::MIME->new;
ok blessed $mp, 'SOAP::Lite::Packager::MIME instantiation';

# check attachment deserialization
print "Attachment deserialization (Content-ID) test(s)...\n";
my $env = $mp->unpackage(<<'EOX');
Content-Type: Multipart/Related; boundary=MIME_boundary; type="text/xml"; start="<claim061400a.xml@claiming-it.com>"
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
      <theSignedForm href="cid:claim061400a.tiff@claiming-it.com"/>
      <theCrashPhoto href="cid:claim061400a.jpeg@claiming-it.com"/>
      <somexml href="cid:claim061400a.somexml@claiming-it.com"/>
      <realxml href="cid:claim061400a.realxml@claiming-it.com"/>
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
Content-Type: image/jpeg
Content-Transfer-Encoding: binary
Content-ID: <claim061402a.jpeg@claiming-it.com>

...Raw JPEG image..
--MIME_boundary
Content-Type: text/plain
Content-Transfer-Encoding: binary
Content-ID: <claim061403a.somexml@claiming-it.com>

<a><b>c</b></a>
--MIME_boundary
Content-Type: text/xml
Content-Transfer-Encoding: binary
Content-ID: <claim061404a.realxml@claiming-it.com>

<a><b>c</b></a>
--MIME_boundary--

EOX

# test to see how how many parts were found:
is @{$mp->parts}, 4, 'number of parts';
isa_ok $mp->parts->[0], "MIME::Entity";
__END__
# Tests to see if data extraction works - TIFF not checked
my @part_data = $mp->find_part( id => '<claim061402a.jpeg@claiming-it.com>' );
ok($part_data[0] eq '...Raw JPEG image..');
@part_data = $mp->find_part( id => '<claim061403a.somexml@claiming-it.com>' );
ok($part_data[0] eq '<a><b>c</b></a>');
@part_data = $mp->find_part( id => '<claim061404a.realxml@claiming-it.com>' );
ok($part_data[0] eq '<a><b>c</b></a>');


# Test: no start parameter specified
$env = $mp->unpackage(<<'EOX');
Content-Type: Multipart/Related; boundary=MIME_boundary; type="text/xml"
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
      <theSignedForm href="cid:claim061400a.tiff@claiming-it.com"/>
      <theCrashPhoto href="cid:claim061400a.jpeg@claiming-it.com"/>
      <somexml href="cid:claim061400a.somexml@claiming-it.com"/>
      <realxml href="cid:claim061400a.realxml@claiming-it.com"/>
      <!-- ... more claim details go here... -->
    </claim:insurance_claim_auto>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>

--MIME_boundary
Content-Type: text/plain
Content-Transfer-Encoding: binary
Content-ID: <claim061403a.somexml@claiming-it.com>

<a><b>c</b></a>
--MIME_boundary--

EOX

# test to see how how many parts were found:
ok(@{$mp->parts} == 1);
# Tests to see if data extraction worked
@part_data = $mp->find_part( id => '<claim061403a.somexml@claiming-it.com>' );
ok($part_data[0] eq '<a><b>c</b></a>');

# test to see if start parameter works if it doesn't point to root
$env = $mp->unpackage(<<'EOX');
Content-Type: Multipart/Related; boundary=MIME_boundary; type="text/xml"; start="<claim061400a.xml@claiming-it.com>"
SOAPAction: http://schemas.risky-stuff.com/Auto-Claim
Content-Description: This is the optional message description.

--MIME_boundary
Content-Type: text/plain
Content-Transfer-Encoding: binary
Content-ID: <claim061403a.somexml@claiming-it.com>

<a><b>c</b></a>
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
      <theSignedForm href="cid:claim061400a.tiff@claiming-it.com"/>
      <theCrashPhoto href="cid:claim061400a.jpeg@claiming-it.com"/>
      <somexml href="cid:claim061400a.somexml@claiming-it.com"/>
      <realxml href="cid:claim061400a.realxml@claiming-it.com"/>
      <!-- ... more claim details go here... -->
    </claim:insurance_claim_auto>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>

--MIME_boundary--
EOX

# test to see how how many parts were found:
ok(@{$mp->parts} == 1);
# Tests to see if data extraction worked
@part_data = $mp->find_part( id => '<claim061403a.somexml@claiming-it.com>' );
ok($part_data[0] eq '<a><b>c</b></a>');

1;
