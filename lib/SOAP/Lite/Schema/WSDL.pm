package SOAP::Lite::Schema::WSDL;

use strict;
use SOAP::Lite;
use SOAP::Lite::Schema;
use vars qw(%imported @ISA);
@ISA = qw(SOAP::Lite::Schema);

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = $class->SUPER::new(@_);
    }
    return $self;
}

sub base {
    my $self = shift->new;
    @_
        ? ($self->{_base} = shift, return $self)
        : return $self->{_base};
}

sub import {
    my $self = shift->new;
    my $s = shift || return;
    my $base = shift || $self->base || die "Missing base argument for ", __PACKAGE__, "\n";

    my @a = $s->import;
    local %imported = %imported;
    foreach (@a) {
        next unless $_->location;
        my $location = URI->new_abs($_->location->value, $base)->as_string;
        if ($imported{$location}++) {
            warn "Recursion loop detected in service description from '$location'. Ignored\n" if $^W;
            return $s;
        }
        my $root = $self->import(
            $self->deserializer->deserialize(
                $self->access($location)
            )->root, $location);

        $root->SOAP::Data::name eq 'definitions' ? $s->set_value($s->value, $root->value) :
        $root->SOAP::Data::name eq 'schema' ? do { # add <types> element if there is no one
        $s->set_value($s->value, $self->deserializer->deserialize('<types></types>')->root) unless $s->types;
        $s->types->set_value($s->types->value, $root) } :
        die "Don't know what to do with '@{[$root->SOAP::Data::name]}' in schema imported from '$location'\n";
    }

    # return the parsed WSDL file
    $s;
}

# TODO - This is woefully incomplete!
sub parse_schema_element {
    my $element = shift;
    # Current element is a complex type
    if (defined($element->complexType)) {
        my @elements = ();
        if (defined($element->complexType->sequence)) {

            foreach my $e ($element->complexType->sequence->element) {
                push @elements,parse_schema_element($e);
            }
        }
        return @elements;
    }
    elsif ($element->simpleType) {
    }
    else {
        return $element;
    }
}

sub parse {
    my $self = shift->new;
    my($s, $service, $port) = @_;
    my @result;

    # handle imports
    $self->import($s);

    # handle descriptions without <service>, aka tModel-type descriptions
    my @services = $s->service;
    my $tns = $s->{'_attr'}->{'targetNamespace'};
    # if there is no <service> element we'll provide it
    @services = $self->deserializer->deserialize(<<"FAKE")->root->service unless @services;
<definitions>
  <service name="@{[$service || 'FakeService']}">
    <port name="@{[$port || 'FakePort']}" binding="@{[$s->binding->name]}"/>
  </service>
</definitions>
FAKE

    my $has_warned = 0;
    foreach (@services) {
        my $name = $_->name;
        next if $service && $service ne $name;
        my %services;
        foreach ($_->port) {
            next if $port && $port ne $_->name;
            my $binding = SOAP::Utils::disqualify($_->binding);
            my $endpoint = ref $_->address ? $_->address->location : undef;
            foreach ($s->binding) {
                # is this a SOAP binding?
                next unless grep { $_->uri eq 'http://schemas.xmlsoap.org/wsdl/soap/' } $_->binding;
                next unless $_->name eq $binding;
                my $default_style = $_->binding->style;
                my $porttype = SOAP::Utils::disqualify($_->type);
                foreach ($_->operation) {
                    my $opername = $_->name;
                    $services{$opername} = {}; # should be initialized in 5.7 and after
                    my $soapaction = $_->operation->soapAction;
                    my $invocationStyle = $_->operation->style || $default_style || "rpc";
                    my $encodingStyle = $_->input->body->use || "encoded";
                    my $namespace = $_->input->body->namespace || $tns;
                    my @parts;
                    foreach ($s->portType) {
                        next unless $_->name eq $porttype;
                        foreach ($_->operation) {
                            next unless $_->name eq $opername;
                            my $inputmessage = SOAP::Utils::disqualify($_->input->message);
                            foreach my $msg ($s->message) {
                                next unless $msg->name eq $inputmessage;
                                if ($invocationStyle eq "document" && $encodingStyle eq "literal") {
#                  warn "document/literal support is EXPERIMENTAL in SOAP::Lite"
#                  if !$has_warned && ($has_warned = 1);
                                    my ($input_ns,$input_name) = SOAP::Utils::splitqname($msg->part->element);
                                    foreach my $schema ($s->types->schema) {
                                        foreach my $element ($schema->element) {
                                            next unless $element->name eq $input_name;
                                            push @parts,parse_schema_element($element);
                                        }
                                        $services{$opername}->{parameters} = [ @parts ];
                                    }
                                }
                                else {
                                    # TODO - support all combinations of doc|rpc/lit|enc.
                                    #warn "$invocationStyle/$encodingStyle is not supported in this version of SOAP::Lite";
                                    @parts = $msg->part;
                                    $services{$opername}->{parameters} = [ @parts ];
                                }
                            }
                        }

                    for ($services{$opername}) {
                        $_->{endpoint}   = $endpoint;
                        $_->{soapaction} = $soapaction;
                        $_->{namespace}  = $namespace;
                        # $_->{parameters} = [@parts];
                    }
                }
            }
        }
    }
    # fix nonallowed characters in package name, and add 's' if started with digit
    for ($name) { s/\W+/_/g; s/^(\d)/s$1/ }
    push @result, $name => \%services;
    }
    return @result;
}

1;

__END__