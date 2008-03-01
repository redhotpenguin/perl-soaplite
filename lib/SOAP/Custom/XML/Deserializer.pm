package SOAP::Custom::XML::Deserializer;

use strict;

use SOAP::Data;
use SOAP::Custom::XML::Data;
use SOAP::Deserializer;

use vars qw(@ISA);
@ISA = qw(SOAP::Deserializer);

sub decode_value {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;
    # base class knows what to do with it
    return $self->SUPER::decode_value($ref) if exists $attrs->{href};

    SOAP::Custom::XML::Data
        -> SOAP::Data::name($name)
        -> attr($attrs)
        -> set_value(ref $children && @$children
            ? map(scalar(($self->decode_object($_))[1]), @$children)
            : $value);
}

1;

__END__