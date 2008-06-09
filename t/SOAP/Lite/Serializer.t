use strict;
use warnings;
use Test::More tests => 17; #qw(no_plan);
use Scalar::Util qw(refaddr);

use_ok qw(SOAP::Lite::Serializer);

# constructor called as class and object method
ok my $serializer = SOAP::Lite::Serializer->new(), 'instantiate object';
is refaddr $serializer, refaddr $serializer->new(), 'new called as object method';

is $serializer->soapversion(), '1.1', 'default soapversion() is >1.1<';

SOAP::Lite::Serializer->prefix('v');
like $serializer->gen_ns(), qr{namesp \d+}x, 'generate namespace prefix';
like $serializer->gen_name(), qr{v-gensym \d+}x, 'generate namespace prefix';

PREFIX: {
    is $serializer->envprefix(), 'soap', 'default envprefix is >soap<';
    is $serializer->encprefix(), 'soapenc', 'default envprefix is >soapenc<';

    my $prefix = 'SOAP-ENV';
    ok $serializer->envprefix('SOAP-ENV'), 'set envprefix';
    is $serializer->envprefix(), $prefix, "envprefix is $prefix";

    # TODO this one must fail
    TODO: {
        local $TODO = 'must fail - prefix already in use';
        eval { $serializer->encprefix('SOAP-ENV') };
        ok $@, 'set encprefix';
    }
    $prefix = 'SOAP-ENC';
    ok $serializer->encprefix($prefix), 'set encprefix';
    is $serializer->encprefix(), $prefix, "encprefix is $prefix";
}

ok my $tag = $serializer->tag('fooxml', {}, undef), 'serialize <fooxml/>';
ok $tag = $serializer->tag('_xml', {}, undef), 'serialize <_xml/>';
eval {
    $tag = $serializer->tag('xml:lang', {}, undef);;
};
like $@, qr{^Element \s 'xml:lang' \s can't \s be \s allowed}x, 'error on <xml:lang/>';
undef $@;
eval {
    $tag = $serializer->tag('xmlfoo', {}, undef);
};
like $@, qr{^Element \s 'xmlfoo' \s can't \s be \s allowed}x, 'error on <xmlfoo/>';

