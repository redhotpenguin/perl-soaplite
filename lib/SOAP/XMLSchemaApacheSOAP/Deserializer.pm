package SOAP::XMLSchemaApacheSOAP::Deserializer;

use strict;

sub as_map {
    my $self = shift;
    return {
        map {
            my $hash = ($self->decode_object($_))[1];
            ($hash->{key} => $hash->{value})
        } @{$_[3] || []}
    };
}
sub as_Map; *as_Map = \&as_map;

# Thank to Kenneth Draper for this contribution
sub as_vector {
    my $self = shift;
    return [ map { scalar(($self->decode_object($_))[1]) } @{$_[3] || []} ];
}
sub as_Vector; *as_Vector = \&as_vector;

1;

__END__