package SOAP::Utils;

use strict;

sub qualify {
    $_[1]
        ? $_[1] =~ /:/
            ? $_[1]
            : join(':', $_[0] || (), $_[1])
        : defined $_[1]
            ? $_[0]
            : ''
    }

sub overqualify (&$) {
    for ($_[1]) {
        &{$_[0]};
        s/^:|:$//g
    }
}

sub disqualify {
    (my $qname = shift) =~ s/^($SOAP::Constants::NSMASK?)://;
    return $qname;
}

sub splitqname {
    local($1,$2);
    $_[0] =~ /^(?:([^:]+):)?(.+)$/;
    return ($1,$2)
}

sub longname {
    defined $_[0]
        ? sprintf('{%s}%s', $_[0], $_[1])
        : $_[1]
}

sub splitlongname {
    local($1,$2);
    $_[0] =~ /^(?:\{(.*)\})?(.+)$/;
    return ($1,$2)
}

# Q: why only '&' and '<' are encoded, but not '>'?
# A: because it is not required according to XML spec.
#
# [http://www.w3.org/TR/REC-xml#syntax]
# The ampersand character (&) and the left angle bracket (<) may appear in
# their literal form only when used as markup delimiters, or within a comment,
# a processing instruction, or a CDATA section. If they are needed elsewhere,
# they must be escaped using either numeric character references or the
# strings "&amp;" and "&lt;" respectively. The right angle bracket (>) may be
# represented using the string "&gt;", and must, for compatibility, be
# escaped using "&gt;" or a character reference when it appears in the
# string "]]>" in content, when that string is not marking the end of a
# CDATA section.

my %encode_attribute = ('&' => '&amp;', '>' => '&gt;', '<' => '&lt;', '"' => '&quot;');
sub encode_attribute { (my $e = $_[0]) =~ s/([&<>\"])/$encode_attribute{$1}/g; $e }

my %encode_data = ('&' => '&amp;', '>' => '&gt;', '<' => '&lt;', "\xd" => '&#xd;');
sub encode_data { my $e = $_[0]; if ($e) { $e =~ s/([&<>\015])/$encode_data{$1}/g; $e =~ s/\]\]>/\]\]&gt;/g; } $e }

# methods for internal tree (SOAP::Lite::Deserializer, SOAP::SOM and SOAP::Serializer)

sub o_qname { $_[0]->[0] }
sub o_attr  { $_[0]->[1] }
sub o_child { ref $_[0]->[2] ? $_[0]->[2] : undef }
sub o_chars { ref $_[0]->[2] ? undef : $_[0]->[2] }
            # $_[0]->[3] is not used. Serializer stores object ID there
sub o_value { $_[0]->[4] }
sub o_lname { $_[0]->[5] }
sub o_lattr { $_[0]->[6] }

sub format_datetime {
    my ($s,$m,$h,$D,$M,$Y) = (@_)[0,1,2,3,4,5];
    my $time = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",($Y+1900),($M+1),$D,$h,$m,$s);
    return $time;
}

# make bytelength that calculates length in bytes regardless of utf/byte settings
# either we can do 'use bytes' or length will count bytes already
BEGIN {
    sub bytelength;
    *bytelength = eval('use bytes; 1') # 5.6.0 and later?
        ? sub { use bytes; length(@_ ? $_[0] : $_) }
        : sub { length(@_ ? $_[0] : $_) };
}

1;

__END__