package SOAP::XMLSchema::Serializer;

use strict;

use vars qw(@ISA);

sub xmlschemaclass {
    my $self = shift;
    return $ISA[0] unless @_;
    @ISA = (shift);
    return $self;
}

1;

__END__