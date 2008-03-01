package SOAP::Server::Object;

use strict;

sub gen_id; *gen_id = \&SOAP::Serializer::gen_id;

my %alive;
my %objects;

sub objects_by_reference {
    shift;
    while (@_) {
        @alive{shift()} = ref $_[0]
            ? shift
            : sub {
                $_[1]-$_[$_[5] ? 5 : 4] > $SOAP::Constants::OBJS_BY_REF_KEEPALIVE
            }
    }
    keys %alive;
}

sub reference {
    my $self = shift;
    my $stamp = time;
    my $object = shift;
    my $id = $stamp . $self->gen_id($object);

    # this is code for garbage collection
    my $time = time;
    my $type = ref $object;
    my @objects = grep { $objects{$_}->[1] eq $type } keys %objects;
    for (grep { $alive{$type}->(scalar @objects, $time, @{$objects{$_}}) } @objects) {
        delete $objects{$_};
    }

    $objects{$id} = [$object, $type, $stamp];
    bless { id => $id } => ref $object;
}

sub references {
    my $self = shift;
    return @_ unless %alive; # small optimization
    return map {
        ref($_) && exists $alive{ref $_}
            ? $self->reference($_)
            : $_
    } @_;
}

sub object {
    my $self = shift;
    my $class = ref($self) || $self;
    my $object = shift;
    return $object unless ref($object) && $alive{ref $object} && exists $object->{id};

    my $reference = $objects{$object->{id}};
    die "Object with specified id couldn't be found\n" unless ref $reference->[0];

    $reference->[3] = time; # last access time
    return $reference->[0]; # reference to actual object
}

sub objects {
    my $self = shift;
    return @_ unless %alive; # small optimization
    return map {
        ref($_) && exists $alive{ref $_} && exists $_->{id}
            ? $self->object($_)
            : $_
    } @_;
}

1;

__END__