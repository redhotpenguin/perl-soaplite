package SOAP::Data;

use strict;

use SOAP::Trace;

use vars qw(@ISA @EXPORT_OK);
use Exporter;
use Carp ();

@ISA = qw(Exporter);
@EXPORT_OK = qw(name type attr value uri);

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = bless {_attr => {}, _value => [], _signature => []} => $class;
        SOAP::Trace::objects('()');
    }
    no strict qw(refs);
    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    while (@_) {
        my $method = shift;
        $self->$method(shift) if $self->can($method)
    }

    return $self;
}

sub name {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__) ? shift->new : __PACKAGE__->new;
    if (@_) {
        my ($name, $uri, $prefix) = shift;
        if ($name) {
            ($uri, $name) = SOAP::Utils::splitlongname($name);
            unless (defined $uri) {
                ($prefix, $name) = SOAP::Utils::splitqname($name);
                $self->prefix($prefix) if defined $prefix;
            } else {
                $self->uri($uri);
            }
        }
        $self->{_name} = $name;

        $self->value(@_) if @_;
        return $self;
    }
    return $self->{_name};
}

sub attr {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    if (@_) {
        $self->{_attr} = shift;
        $self->value(@_) if @_;
        return $self
    }
    return $self->{_attr};
}

sub type {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    if (@_) {
        $self->{_type} = shift;
        $self->value(@_) if @_;
        return $self;
    }
    if (!defined $self->{_type} && (my @types = grep {/^\{$SOAP::Constants::NS_XSI_ALL}type$/o} keys %{$self->{_attr}})) {
        $self->{_type} = (SOAP::Utils::splitlongname(delete $self->{_attr}->{shift(@types)}))[1];
    }
    return $self->{_type};
}

BEGIN {
    no strict 'refs';
    for my $method (qw(root mustUnderstand)) {
        my $field = '_' . $method;
        *$method = sub {
        my $attr = $method eq 'root'
            ? "{$SOAP::Constants::NS_ENC}$method"
            : "{$SOAP::Constants::NS_ENV}$method";
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new
                : __PACKAGE__->new;
            if (@_) {
                $self->{_attr}->{$attr} = $self->{$field} = shift() ? 1 : 0;
                $self->value(@_) if @_;
                return $self;
            }
            $self->{$field} = SOAP::Lite::Deserializer::XMLSchemaSOAP1_2->as_boolean($self->{_attr}->{$attr})
                if !defined $self->{$field} && defined $self->{_attr}->{$attr};
            return $self->{$field};
        }
    }

    for my $method (qw(actor encodingStyle)) {
        my $field = '_' . $method;
        *$method = sub {
            my $attr = "{$SOAP::Constants::NS_ENV}$method";
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new()
                : __PACKAGE__->new();
            if (@_) {
                $self->{_attr}->{$attr} = $self->{$field} = shift;
                $self->value(@_) if @_;
                return $self;
            }
            $self->{$field} = $self->{_attr}->{$attr}
                if !defined $self->{$field} && defined $self->{_attr}->{$attr};
            return $self->{$field};
        }
    }
}

sub prefix {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    return $self->{_prefix} unless @_;
    $self->{_prefix} = shift;
    $self->value(@_) if @_;
    return $self;
}

sub uri {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    return $self->{_uri} unless @_;
    my $uri = $self->{_uri} = shift;
    warn "Usage of '::' in URI ($uri) deprecated. Use '/' instead\n"
        if defined $uri && $^W && $uri =~ /::/;
    $self->value(@_) if @_;
    return $self;
}

sub set_value {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    $self->{_value} = [@_];
    return $self;
}

sub value {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new;
    (@_)
        ? ($self->set_value(@_), return $self)
        : wantarray
            ? return @{$self->{_value}}
            : return $self->{_value}->[0];
}

sub signature {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    (@_)
        ? ($self->{_signature} = shift, return $self)
        : (return $self->{_signature});
}

1;

__END__