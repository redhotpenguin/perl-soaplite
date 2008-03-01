package SOAP::Fault;

use strict;

use Carp ();

use overload fallback => 1, '""' => "stringify";

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = bless {} => $class;
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()"
        if $^W && (@_ & 1);

    no strict qw(refs);
    while (@_) {
        my $method = shift;
        $self->$method(shift)
            if $self->can($method)
    }

    return $self;
}

sub stringify {
    my $self = shift;
    return join ': ', $self->faultcode, $self->faultstring;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(faultcode faultstring faultactor faultdetail)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new
                : __PACKAGE__->new;
            if (@_) {
                $self->{$field} = shift;
                return $self
            }
            return $self->{$field};
        }
    }
    *detail = \&faultdetail;
}

1;

__END__