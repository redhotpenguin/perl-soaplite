package SOAP::Cloneable;

use strict;

sub clone {
    my $self = shift;

    return unless ref $self && UNIVERSAL::isa($self => __PACKAGE__);

    my $clone = bless {} => ref($self);
    for (keys %$self) {
        my $value = $self->{$_};
        $clone->{$_} = ref $value && UNIVERSAL::isa($value => __PACKAGE__) ? $value->clone : $value;
    }
    return $clone;
}

1;

__END__