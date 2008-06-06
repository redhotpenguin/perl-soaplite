package SOAP::Serializer;

die "deprecated";

use strict;

# TODO check and remove dependency
use SOAP::Lite;

use SOAP::Cloneable;
use SOAP::XMLSchema::Serializer;
use SOAP::Trace;
use SOAP::Lite::Utils;
use SOAP::Utils;
use SOAP::Lite::Deserializer;
use SOAP::Parser;
use SOAP::Data;

use Carp ();
use vars qw(@ISA);

@ISA = qw(SOAP::Cloneable SOAP::XMLSchema::Serializer);

BEGIN {
    # namespaces and anonymous data structures
    my $ns   = 0;
    my $name = 0;
    my $prefix = 'c-';
    sub gen_ns { 'namesp' . ++$ns }
    sub gen_name { join '', $prefix, 'gensym', ++$name }
    sub prefix { $prefix =~ s/^[^\-]+-/$_[1]-/; $_[0]; }
}

sub BEGIN {
    no strict 'refs';

    __PACKAGE__->__mk_accessors(qw(readable level seen autotype typelookup attr maptype
        namespaces multirefinplace encoding signature on_nonserialized context
        ns_uri ns_prefix use_default_ns));

    for my $method (qw(method fault freeform)) { # aliases for envelope
        *$method = sub { shift->envelope($method => @_) }
    }
    # Is this necessary? Seems like work for nothing when a user could just use
    # SOAP::Utils directly.
    # for my $method (qw(qualify overqualify disqualify)) { # import from SOAP::Utils
    #   *$method = \&{'SOAP::Utils::'.$method};
    # }
}

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;

    my $class = $self;
    $self = bless {
        _level => 0,
        _autotype => 1,
        _readable => 0,
        _ns_uri => '',
        _ns_prefix => '',
        _use_default_ns => 1,
        _multirefinplace => 0,
        _seen => {},
        _typelookup => {
           'base64Binary' =>
              [10, sub {$_[0] =~ /[^\x09\x0a\x0d\x20-\x7f]/ }, 'as_base64Binary'],
           'zerostring' =>
               [12, sub { $_[0] =~ /^0\d+$/ }, 'as_string'],
            # int (and actually long too) are subtle: the negative range is one greater...
            'int'  =>
               [20, sub {$_[0] =~ /^([+-]?\d+)$/ && ($1 <= 2147483647) && ($1 >= -2147483648); }, 'as_int'],
            'long' =>
               [25, sub {$_[0] =~ /^([+-]?\d+)$/ && $1 <= 9223372036854775807;}, 'as_long'],
            'float'  =>
               [30, sub {$_[0] =~ /^(-?(?:\d+(?:\.\d*)?|\.\d+|NaN|INF)|([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?)$/}, 'as_float'],
            'gMonth' =>
               [35, sub { $_[0] =~ /^--\d\d--(-\d\d:\d\d)?$/; }, 'as_gMonth'],
            'gDay' =>
               [40, sub { $_[0] =~ /^---\d\d(-\d\d:\d\d)?$/; }, 'as_gDay'],
            'gYear' =>
               [45, sub { $_[0] =~ /^-?\d\d\d\d(-\d\d:\d\d)?$/; }, 'as_gYear'],
            'gMonthDay' =>
               [50, sub { $_[0] =~ /^-\d\d-\d\d(-\d\d:\d\d)?$/; }, 'as_gMonthDay'],
            'gYearMonth' =>
               [55, sub { $_[0] =~ /^-?\d\d\d\d-\d\d(Z|([+-]\d\d:\d\d))?$/; }, 'as_gYearMonth'],
            'date' =>
               [60, sub { $_[0] =~ /^-?\d\d\d\d-\d\d-\d\d(Z|([+-]\d\d:\d\d))?$/; }, 'as_date'],
            'time' =>
               [70, sub { $_[0] =~ /^\d\d:\d\d:\d\d(\.\d\d\d)?(Z|([+-]\d\d:\d\d))?$/; }, 'as_time'],
            'dateTime' =>
               [75, sub { $_[0] =~ /^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d\d\d)?(Z|([+-]\d\d:\d\d))?$/; }, 'as_dateTime'],
            'duration' =>
               [80, sub { $_[0] !~m{^-?PT?$} && $_[0] =~ m{^
                        -?   # a optional - sign
                        P
                        (:? \d+Y )?
                        (:? \d+M )?
                        (:? \d+D )?
                        (:?
                            T(:?\d+H)?
                            (:?\d+M)?
                            (:?\d+S)?
                        )?
                        $
                    }x;
               }, 'as_duration'],
            'boolean' =>
               [90, sub { $_[0] =~ /^(true|false)$/i; }, 'as_boolean'],
            'anyURI' =>
               [95, sub { $_[0] =~ /^(urn:|http:\/\/)/i; }, 'as_anyURI'],
            'string' =>
               [100, sub {1}, 'as_string'],
        },
        _encoding => 'UTF-8',
        _objectstack => {},
        _signature => [],
        _maptype => {},
        _on_nonserialized => sub {Carp::carp "Cannot marshall @{[ref shift]} reference" if $^W; return},
        _encodingStyle => $SOAP::Constants::NS_ENC,
        _attr => {
            "{$SOAP::Constants::NS_ENV}encodingStyle" => $SOAP::Constants::NS_ENC,
        },
        _namespaces => {},
        _soapversion => SOAP::Lite->soapversion,
    } => $class;
    $self->register_ns($SOAP::Constants::NS_ENC,$SOAP::Constants::PREFIX_ENC);
    $self->register_ns($SOAP::Constants::NS_ENV,$SOAP::Constants::PREFIX_ENV)
        if $SOAP::Constants::PREFIX_ENV;
    $self->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA);
    SOAP::Trace::objects('()');

    no strict qw(refs);
    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    while (@_) { my $method = shift; $self->$method(shift) if $self->can($method) }

    return $self;
}

sub ns {
    my $self = shift;
    $self = $self->new() if not ref $self;
    if (@_) {
        my ($u,$p) = @_;
        my $prefix;

        if ($p) {
            $prefix = $p;
        }
        elsif (!$p && !($prefix = $self->find_prefix($u))) {
            $prefix = gen_ns;
        }

        $self->{'_ns_uri'}         = $u;
        $self->{'_ns_prefix'}      = $prefix;
        $self->{'_use_default_ns'} = 0;
        # $self->register_ns($u,$prefix);
        $self->{'_namespaces'}->{$u} = $prefix;
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub default_ns {
    my $self = shift;
    $self = $self->new() if not ref $self;
    if (@_) {
        my ($u) = @_;
        $self->{'_ns_uri'}         = $u;
        $self->{'_ns_prefix'}      = '';
        $self->{'_use_default_ns'} = 1;
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub use_prefix {
    my $self = shift;
    $self = $self->new() if not ref $self;
    warn 'use_prefix has been deprecated. if you wish to turn off or on the '
        . 'use of a default namespace, then please use either ns(uri) or default_ns(uri)';
    if (@_) {
        my $use = shift;
        $self->{'_use_default_ns'} = !$use || 0;
        return $self;
    } else {
        return $self->{'_use_default_ns'};
    }
}
sub uri {
    my $self = shift;
    $self = $self->new() if not ref $self;
#    warn 'uri has been deprecated. if you wish to set the namespace for the request, then please use either ns(uri) or default_ns(uri)';
    if (@_) {
        my $ns = shift;
        if ($self->{_use_default_ns}) {
           $self->default_ns($ns);
        }
        else {
           $self->ns($ns);
        }
#       $self->{'_ns_uri'} = $ns;
#       $self->register_ns($self->{'_ns_uri'}) if (!$self->{_use_default_ns});
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub encodingStyle {
    my $self = shift;
    $self = $self->new() if not ref $self;
    return $self->{'_encodingStyle'} unless @_;

    my $cur_style = $self->{'_encodingStyle'};
    delete($self->{'_namespaces'}->{$cur_style});

    my $new_style = shift;
    if ($new_style eq "") {
        delete($self->{'_attr'}->{"{$SOAP::Constants::NS_ENV}encodingStyle"});
    }
    else {
        $self->{'_attr'}->{"{$SOAP::Constants::NS_ENV}encodingStyle"} = $new_style;
        $self->{'_namespaces'}->{$new_style} = $SOAP::Constants::PREFIX_ENC;
    }
}

# TODO - changing SOAP version can affect previously set encodingStyle
sub soapversion {
    my $self = shift;
    return $self->{_soapversion} unless @_;
    return $self if $self->{_soapversion} eq SOAP::Lite->soapversion;
    $self->{_soapversion} = shift;

    $self->attr({
        "{$SOAP::Constants::NS_ENV}encodingStyle" => $SOAP::Constants::NS_ENC,
    });
    $self->namespaces({
        $SOAP::Constants::NS_ENC => $SOAP::Constants::PREFIX_ENC,
        $SOAP::Constants::PREFIX_ENV ? ($SOAP::Constants::NS_ENV => $SOAP::Constants::PREFIX_ENV) : (),
    });
    $self->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA);

    return $self;
}

sub xmlschema {
    my $self = shift->new;
    return $self->{_xmlschema} unless @_;

    my @schema;
    if ($_[0]) {
        @schema = grep {/XMLSchema/ && /$_[0]/} keys %SOAP::Constants::XML_SCHEMAS;
        Carp::croak "More than one schema match parameter '$_[0]': @{[join ', ', @schema]}" if @schema > 1;
        Carp::croak "No schema match parameter '$_[0]'" if @schema != 1;
    }

    # do nothing if current schema is the same as new
    return $self if $self->{_xmlschema} && $self->{_xmlschema} eq $schema[0];

    my $ns = $self->namespaces;

    # delete current schema from namespaces
    if (my $schema = $self->{_xmlschema}) {
        delete $ns->{$schema};
        delete $ns->{"$schema-instance"};
    }

    # add new schema into namespaces
    if (my $schema = $self->{_xmlschema} = shift @schema) {
        $ns->{$schema} = 'xsd';
        $ns->{"$schema-instance"} = 'xsi';
    }

    # and here is the class serializer should work with
    my $class = exists $SOAP::Constants::XML_SCHEMAS{$self->{_xmlschema}}
        ? $SOAP::Constants::XML_SCHEMAS{$self->{_xmlschema}} . '::Serializer'
        : $self;

    $self->xmlschemaclass($class);

    return $self;
}

sub envprefix {
    my $self = shift->new();
    return $self->namespaces->{$SOAP::Constants::NS_ENV} unless @_;
    $self->namespaces->{$SOAP::Constants::NS_ENV} = shift;
    return $self;
}

sub encprefix {
    my $self = shift->new();
    return $self->namespaces->{$SOAP::Constants::NS_ENC} unless @_;
    $self->namespaces->{$SOAP::Constants::NS_ENC} = shift;
    return $self;
}

sub gen_id { sprintf "%U", $_[1] }

sub multiref_object {
    my ($self, $object) = @_;
    my $id = $self->gen_id($object);
    my $seen = $self->seen;
    $seen->{$id}->{count}++;
    $seen->{$id}->{multiref} ||= $seen->{$id}->{count} > 1;
    $seen->{$id}->{value} = $object;
    $seen->{$id}->{recursive} ||= 0;
    return $id;
}

sub recursive_object {
    my $self = shift;
    $self->seen->{$self->gen_id(shift)}->{recursive} = 1;
}

sub is_href {
    my $self = shift;
    my $seen = $self->seen->{shift || return} or return;
    return 1 if $seen->{id};
    return $seen->{multiref}
        && !($seen->{id} = (shift
            || $seen->{recursive}
            || $seen->{multiref} && $self->multirefinplace));
}

sub multiref_anchor {
    my $seen = shift->seen->{my $id = shift || return undef};
    return $seen->{multiref} ? "ref-$id" : undef;
}

sub encode_multirefs {
    my $self = shift;
    return if $self->multirefinplace();

    my $seen = $self->seen();
    map { $_->[1]->{_id} = 1; $_ }
        map { $self->encode_object($seen->{$_}->{value}) }
            grep { $seen->{$_}->{multiref} && !$seen->{$_}->{recursive} }
                keys %$seen;
}

sub maptypetouri {
    my($self, $type, $simple) = @_;

    return $type unless defined $type;
    my($prefix, $name) = SOAP::Utils::splitqname($type);

    unless (defined $prefix) {
        $name =~ s/__|\./::/g;
        $self->maptype->{$name} = $simple
            ? die "Schema/namespace for type '$type' is not specified\n"
            : $SOAP::Constants::NS_SL_PERLTYPE
                unless exists $self->maptype->{$name};
        $type = $self->maptype->{$name}
            ? SOAP::Utils::qualify($self->namespaces->{$self->maptype->{$name}} ||= gen_ns, $type)
            : undef;
    }
    return $type;
}

sub encode_object {
    my($self, $object, $name, $type, $attr) = @_;

    $attr ||= {};

    return $self->encode_scalar($object, $name, $type, $attr)
        unless ref $object;

    my $id = $self->multiref_object($object);

    use vars '%objectstack';           # we'll play with symbol table
    local %objectstack = %objectstack; # want to see objects ONLY in the current tree
    # did we see this object in current tree? Seems to be recursive refs
    $self->recursive_object($object) if ++$objectstack{$id} > 1;
    # return if we already saw it twice. It should be already properly serialized
    return if $objectstack{$id} > 2;

    if (UNIVERSAL::isa($object => 'SOAP::Data')) {
        # use $object->SOAP::Data:: to enable overriding name() and others in inherited classes
        $object->SOAP::Data::name($name)
            unless defined $object->SOAP::Data::name;

        # apply ->uri() and ->prefix() which can modify name and attributes of
        # element, but do not modify SOAP::Data itself
        my($name, $attr) = $self->fixattrs($object);
        $attr = $self->attrstoqname($attr);

        my @realvalues = $object->SOAP::Data::value;
        return [$name || gen_name, $attr] unless @realvalues;

        my $method = "as_" . ($object->SOAP::Data::type || '-'); # dummy type if not defined
        # try to call method specified for this type
        no strict qw(refs);
        my @values = map {
            # store null/nil attribute if value is undef
            local $attr->{SOAP::Utils::qualify(xsi => $self->xmlschemaclass->nilValue)} = $self->xmlschemaclass->as_undef(1)
                unless defined;
            $self->can($method) && $self->$method($_, $name || gen_name, $object->SOAP::Data::type, $attr)
                || $self->typecast($_, $name || gen_name, $object->SOAP::Data::type, $attr)
                || $self->encode_object($_, $name, $object->SOAP::Data::type, $attr)
        } @realvalues;
        $object->SOAP::Data::signature([map {join $;, $_->[0], SOAP::Utils::disqualify($_->[1]->{'xsi:type'} || '')} @values]) if @values;
        return wantarray ? @values : $values[0];
    }

    my $class = ref $object;

    if ($class !~ /^(?:SCALAR|ARRAY|HASH|REF)$/o) {
        # we could also check for CODE|GLOB|LVALUE, but we cannot serialize
        # them anyway, so they'll be cought by check below
        $class =~ s/::/__/g;

        $name = $class if !defined $name;
        $type = $class if !defined $type && $self->autotype;

        my $method = 'as_' . $class;
        if ($self->can($method)) {
            no strict qw(refs);
            my $encoded = $self->$method($object, $name, $type, $attr);
            return $encoded if ref $encoded;
            # return only if handled, otherwise handle with default handlers
        }
    }

    if (UNIVERSAL::isa($object => 'REF') || UNIVERSAL::isa($object => 'SCALAR')) {
        return $self->encode_scalar($object, $name, $type, $attr);
    }
    elsif (UNIVERSAL::isa($object => 'ARRAY')) {
        # Added in SOAP::Lite 0.65_6 to fix an XMLRPC bug
        return $self->encodingStyle eq ""
            || $self->isa('XMLRPC::Serializer')
                ? $self->encode_array($object, $name, $type, $attr)
                : $self->encode_literal_array($object, $name, $type, $attr);
    }
    elsif (UNIVERSAL::isa($object => 'HASH')) {
        return $self->encode_hash($object, $name, $type, $attr);
    }
    else {
        return $self->on_nonserialized->($object);
    }
}

sub encode_scalar {
    my($self, $value, $name, $type, $attr) = @_;
    $name ||= gen_name;

    my $schemaclass = $self->xmlschemaclass;

    # null reference
    return [$name, {%$attr, SOAP::Utils::qualify(xsi => $schemaclass->nilValue) => $schemaclass->as_undef(1)}] unless defined $value;

    # object reference
    return [$name, {'xsi:type' => $self->maptypetouri($type), %$attr}, [$self->encode_object($$value)], $self->gen_id($value)] if ref $value;

    # autodefined type
    if ($self->autotype) {
        my $lookup = $self->typelookup();
        no strict qw(refs);
        for (sort {$lookup->{$a}->[0] <=> $lookup->{$b}->[0]} keys %$lookup) {
            my $method = $lookup->{$_}->[2];
            return $self->can($method) && $self->$method($value, $name, $type, $attr)
                || $method->($value, $name, $type, $attr)
                    if $lookup->{$_}->[1]->($value);
        }
    }

    # invariant
    return [$name, $attr, $value];
}

sub encode_array {
    my($self, $array, $name, $type, $attr) = @_;
    my $items = 'item';

    # If typing is disabled, just serialize each of the array items
    # with no type information, each using the specified name,
    # and do not crete a wrapper array tag.
    if (!$self->autotype) {
        $name ||= gen_name;
        return map {$self->encode_object($_, $name)} @$array;
    }

    # TODO: add support for multidimensional, partially transmitted and sparse arrays
    my @items = map {$self->encode_object($_, $items)} @$array;
    my $num = @items;
    my($arraytype, %types) = '-';
    for (@items) { $arraytype = $_->[1]->{'xsi:type'} || '-'; $types{$arraytype}++ }
    $arraytype = sprintf "%s\[$num]", keys %types > 1 || $arraytype eq '-' ? SOAP::Utils::qualify(xsd => $self->xmlschemaclass->anyTypeValue) : $arraytype;

    # $type = SOAP::Utils::qualify($self->encprefix => 'Array') if $self->autotype && !defined $type;
    $type = qualify($self->encprefix => 'Array') if !defined $type;
    return [$name || SOAP::Utils::qualify($self->encprefix => 'Array'),
          {
              SOAP::Utils::qualify($self->encprefix => 'arrayType') => $arraytype,
              'xsi:type' => $self->maptypetouri($type), %$attr
          },
          [@items],
          $self->gen_id($array)
    ];
}

# Will encode arrays using doc-literal style
sub encode_literal_array {
    my($self, $array, $name, $type, $attr) = @_;

    # If typing is disabled, just serialize each of the array items
    # with no type information, each using the specified name,
    # and do not crete a wrapper array tag.
    if (!$self->autotype) {
        $name ||= gen_name;
        return map {$self->encode_object($_, $name)} @$array;
    }

    my $items = 'item';

    # TODO: add support for multidimensional, partially transmitted and sparse arrays
    my @items = map {$self->encode_object($_, $items)} @$array;
    my $num = @items;
    my($arraytype, %types) = '-';
    for (@items) {
       $arraytype = $_->[1]->{'xsi:type'} || '-';
       $types{$arraytype}++
    }
    $arraytype = sprintf "%s\[$num]", keys %types > 1 || $arraytype eq '-'
        ? SOAP::Utils::qualify(xsd => $self->xmlschemaclass->anyTypeValue)
        : $arraytype;

    $type = SOAP::Utils::qualify($self->encprefix => 'Array')
        if !defined $type;

    return [$name || SOAP::Utils::qualify($self->encprefix => 'Array'),
        {
            SOAP::Utils::qualify($self->encprefix => 'arrayType') => $arraytype,
            'xsi:type' => $self->maptypetouri($type), %$attr
        },
        [ @items ],
        $self->gen_id($array)
    ];
}

sub encode_hash {
    my($self, $hash, $name, $type, $attr) = @_;

    if ($self->autotype && grep {!/$SOAP::Constants::ELMASK/o} keys %$hash) {
        warn qq!Cannot encode @{[$name ? "'$name'" : 'unnamed']} element as 'hash'. Will be encoded as 'map' instead\n! if $^W;
        return $self->as_map($hash, $name || gen_name, $type, $attr);
    }

    $type = 'SOAPStruct'
        if $self->autotype && !defined($type) && exists $self->maptype->{SOAPStruct};
    return [$name || gen_name,
          $self->autotype ? {'xsi:type' => $self->maptypetouri($type), %$attr} : { %$attr },
          [map {$self->encode_object($hash->{$_}, $_)} keys %$hash],
          $self->gen_id($hash)
    ];
}

sub as_ordered_hash {
    my ($self, $value, $name, $type, $attr) = @_;
    die "Not an ARRAY reference for 'ordered_hash' type" unless UNIVERSAL::isa($value => 'ARRAY');
    return [ $name, $attr,
        [map{$self->encode_object(@{$value}[2*$_+1,2*$_])} 0..$#$value/2 ],
        $self->gen_id($value)
    ];
}

sub as_map {
    my ($self, $value, $name, $type, $attr) = @_;
    die "Not a HASH reference for 'map' type" unless UNIVERSAL::isa($value => 'HASH');
    my $prefix = ($self->namespaces->{$SOAP::Constants::NS_APS} ||= 'apachens');
    my @items = map {
        $self->encode_object(
            SOAP::Data->type(
                ordered_hash => [
                    key => $_,
                    value => $value->{$_}
                ]
            ),
            'item',
            ''
        )} keys %$value;
    return [
        $name,
        {'xsi:type' => "$prefix:Map", %$attr},
        [@items],
        $self->gen_id($value)
    ];
}

sub as_xml {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    return [$name, {'_xml' => 1}, $value];
}

sub typecast {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    return if ref $value; # skip complex object, caller knows how to deal with it
    return if $self->autotype && !defined $type; # we don't know, autotype knows
    return [$name,
          {(defined $type && $type gt '' ? ('xsi:type' => $self->maptypetouri($type, 'simple type')) : ()), %$attr},
          $value
    ];
}

sub register_ns {
    my $self = shift->new();
    my ($ns,$prefix) = @_;
    $prefix = gen_ns if !$prefix;
    $self->{'_namespaces'}->{$ns} = $prefix if $ns;
}

sub find_prefix {
    my ($self, $ns) = @_;
    return (exists $self->{'_namespaces'}->{$ns})
        ? $self->{'_namespaces'}->{$ns}
        : ();
}

sub fixattrs {
    my $self = shift;
    my $data = shift;
    my($name, $attr) = ($data->SOAP::Data::name, {%{$data->SOAP::Data::attr}});
    my($xmlns, $prefix) = ($data->uri, $data->prefix);
    unless (defined($xmlns) || defined($prefix)) {
        $self->register_ns($xmlns,$prefix) unless ($self->use_default_ns);
        return ($name, $attr);
    }
    $name ||= gen_name; # local name
    $prefix = gen_ns if !defined $prefix && $xmlns gt '';
    $prefix = ''
        if defined $xmlns && $xmlns eq ''
            || defined $prefix && $prefix eq '';

    $attr->{join ':', xmlns => $prefix || ()} = $xmlns if defined $xmlns;
    $name = join ':', $prefix, $name if $prefix;

    $self->register_ns($xmlns,$prefix) unless ($self->use_default_ns);

    return ($name, $attr);

}

sub toqname {
    my $self = shift;
    my $long = shift;

    return $long unless $long =~ /^\{(.*)\}(.+)$/;
    return SOAP::Utils::qualify $self->namespaces->{$1} ||= gen_ns, $2;
}

sub attrstoqname {
    my $self = shift;
    my $attrs = shift;

    return {
        map { /^\{(.*)\}(.+)$/
            ? ($self->toqname($_) => $2 eq 'type'
                || $2 eq 'arrayType'
                    ? $self->toqname($attrs->{$_})
                    : $attrs->{$_})
            : ($_ => $attrs->{$_})
        } keys %$attrs
    };
}

sub tag {
    my ($self, $tag, $attrs, @values) = @_;
    my $value = join '', @values;
    my $level = $self->level;
    my $indent = $self->readable ? ' ' x (($level-1)*2) : '';

    # check for special attribute
    return "$indent$value" if exists $attrs->{_xml} && delete $attrs->{_xml};

    die "Element '$tag' can't be allowed in valid XML message. Died."
        if $tag !~ /^(?![xX][mM][lL])$SOAP::Constants::NSMASK$/o;

    my $prolog = $self->readable ? "\n" : "";
    my $epilog = $self->readable ? "\n" : "";
    my $tagjoiner = " ";
    if ($level == 1) {
        my $namespaces = $self->namespaces;
        foreach (keys %$namespaces) {
            $attrs->{SOAP::Utils::qualify(xmlns => $namespaces->{$_})} = $_
        }
        $prolog = qq!<?xml version="1.0" encoding="@{[$self->encoding]}"?>!
            if defined $self->encoding;
        $prolog .= "\n" if $self->readable;
        $tagjoiner = " \n".(' ' x (($level+1) * 2)) if $self->readable;
    }
    my $tagattrs = join($tagjoiner, '',
        map { sprintf '%s="%s"', $_, SOAP::Utils::encode_attribute($attrs->{$_}) }
            grep { $_ && defined $attrs->{$_} && ($_ ne 'xsi:type' || $attrs->{$_} ne '') }
                keys %$attrs);

    if ($value gt '') {
        return sprintf("$prolog$indent<%s%s>%s%s</%s>$epilog",$tag,$tagattrs,$value,($value =~ /^\s*</ ? $indent : ""),$tag);
    }
    else {
        return sprintf("$prolog$indent<%s%s />$epilog$indent",$tag,$tagattrs);
    }
}

sub xmlize {
    my $self = shift;
    my($name, $attrs, $values, $id) = @{+shift};
    $attrs ||= {};

    local $self->{_level} = $self->{_level} + 1;
    return $self->tag($name, $attrs)
        unless defined $values;
    return $self->tag($name, $attrs, $values)
        unless UNIVERSAL::isa($values => 'ARRAY');
    return $self->tag($name, {%$attrs, href => '#'.$self->multiref_anchor($id)})
        if $self->is_href($id, delete($attrs->{_id}));
    return $self->tag($name,
        {
            %$attrs, id => $self->multiref_anchor($id)
        },
        map {$self->xmlize($_)} @$values
    );
}

sub uriformethod {
    my $self = shift;

    my $method_is_data = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Data');

    # drop prefix from method that could be string or SOAP::Data object
    my($prefix, $method) = $method_is_data
        ? ($_[0]->prefix, $_[0]->name)
        : SOAP::Utils::splitqname($_[0]);

    my $attr = {reverse %{$self->namespaces}};
    # try to define namespace that could be stored as
    #   a) method is SOAP::Data
    #        ? attribute in method's element as xmlns= or xmlns:${prefix}=
    #        : uri
    #   b) attribute in Envelope element as xmlns= or xmlns:${prefix}=
    #   c) no prefix or prefix equal serializer->envprefix
    #        ? '', but see coment below
    #        : die with error message
    my $uri = $method_is_data
        ? ref $_[0]->attr && ($_[0]->attr->{$prefix ? "xmlns:$prefix" : 'xmlns'} || $_[0]->uri)
        : $self->uri;

    defined $uri or $uri = $attr->{$prefix || ''};

    defined $uri or $uri = !$prefix || $prefix eq $self->envprefix
    # still in doubts what should namespace be in this case
    # but will keep it like this for now and be compatible with our server
        ? ( $method_is_data
            && $^W
            && warn("URI is not provided as an attribute for method ($method)\n"),
            ''
            )
        : die "Can't find namespace for method ($prefix:$method)\n";

    return ($uri, $method);
}

sub serialize { SOAP::Trace::trace('()');
    my $self = shift->new;
    @_ == 1 or Carp::croak "serialize() method accepts one parameter";

    $self->seen({}); # reinitialize multiref table
    my($encoded) = $self->encode_object($_[0]);

    # now encode multirefs if any
    #                 v -------------- subelements of Envelope
    push(@{$encoded->[2]}, $self->encode_multirefs) if ref $encoded->[2];
    return $self->xmlize($encoded);
}

sub envelope {
    SOAP::Trace::trace('()');
    my $self = shift->new;
    my $type = shift;
    my(@parameters, @header);
    for (@_) {
        # Find all the SOAP Headers
        if (defined($_) && ref($_) && UNIVERSAL::isa($_ => 'SOAP::Header')) {
            push(@header, $_);
        }
        # Find all the SOAP Message Parts (attachments)
        elsif (defined($_) && ref($_) && $self->context
            && $self->context->packager->is_supported_part($_)
        ) {
            $self->context->packager->push_part($_);
        }
        # Find all the SOAP Body elements
        else {
            # proposed resolution for [ 1700326 ] encode_data called incorrectly in envelope
            # push(@parameters, $_);
            push (@parameters, SOAP::Utils::encode_data($_));
        }
    }
    my $header = @header ? SOAP::Data->set_value(@header) : undef;
    my($body,$parameters);
    if ($type eq 'method' || $type eq 'response') {
        SOAP::Trace::method(@parameters);

        my $method = shift(@parameters);
        #  or die "Unspecified method for SOAP call\n";

        $parameters = @parameters ? SOAP::Data->set_value(@parameters) : undef;
        if (!defined($method)) {}
        elsif (UNIVERSAL::isa($method => 'SOAP::Data')) {
            $body = $method;
        }
        elsif ($self->use_default_ns) {
            if ($self->{'_ns_uri'}) {
                $body = SOAP::Data->name($method)
                    ->attr({'xmlns' => $self->{'_ns_uri'} } );
            }
            else {
                $body = SOAP::Data->name($method);
            }
        }
        else {
            # Commented out by Byrne on 1/4/2006 - to address default namespace problems
            #      $body = SOAP::Data->name($method)->uri($self->{'_ns_uri'});
            #      $body = $body->prefix($self->{'_ns_prefix'}) if ($self->{'_ns_prefix'});

            # Added by Byrne on 1/4/2006 - to avoid the unnecessary creation of a new
            # namespace
            # Begin New Code (replaces code commented out above)
            $body = SOAP::Data->name($method);
            my $pre = $self->find_prefix($self->{'_ns_uri'});
            $body = $body->prefix($pre) if ($self->{'_ns_prefix'});
            # End new code
        }

        # Set empty value without SOAP::Utils::encode_data to prevent
        # the use of xsi:nil="true" on the method
        # Banned by WS-I basic profile
        # See http://www.ws-i.org/Profiles/BasicProfile-1.2.html#R2211
        $body->set_value($parameters ? \$parameters : ()) if $body;
    }
    elsif ($type eq 'fault') {
        SOAP::Trace::fault(@parameters);
        # parameters[1] needs to be escaped - thanks to aka_hct at gmx dot de
        # commented on 2001/03/28 because of failing in ApacheSOAP
        # need to find out more about it
        # -> attr({'xmlns' => ''})
        # Parameter order fixed thanks to Tom Fischer
        $body = SOAP::Data-> name(SOAP::Utils::qualify($self->envprefix => 'Fault'))
          -> value(\SOAP::Data->set_value(
                SOAP::Data->name(faultcode => SOAP::Utils::qualify($self->envprefix => $parameters[0]))->type(""),
                SOAP::Data->name(faultstring => SOAP::Utils::encode_data($parameters[1]))->type(""),
                defined($parameters[3])
                    ? SOAP::Data->name(faultactor => $parameters[3])->type("")
                    : (),
                defined($parameters[2])
                    ? SOAP::Data->name(detail => do{
                        my $detail = $parameters[2];
                        ref $detail
                            ? \$detail
                            : $detail
                    })
                    : (),
        ));
    }
    elsif ($type eq 'freeform') {
        SOAP::Trace::freeform(@parameters);
        $body = SOAP::Data->set_value(@parameters);
    }
    elsif (!defined($type)) {
        # This occurs when the Body is intended to be null. When no method has been
        # passed in of any kind.
    }
    else {
        die "Wrong type of envelope ($type) for SOAP call\n";
    }

    $self->seen({}); # reinitialize multiref table
    # Build the envelope
    # Right now it is possible for $body to be a SOAP::Data element that has not
    # XML escaped any values. How do you remedy this?
    my($encoded) = $self->encode_object(
        SOAP::Data->name(
            SOAP::Utils::qualify($self->envprefix => 'Envelope') => \SOAP::Data->value(
                ($header
                    ? SOAP::Data->name( SOAP::Utils::qualify($self->envprefix => 'Header') => \$header)
                    : ()
                ),
                ($body
                    ? SOAP::Data->name(SOAP::Utils::qualify($self->envprefix => 'Body') => \$body)
                    : SOAP::Data->name(SOAP::Utils::qualify($self->envprefix => 'Body')) ),
            )
        )->attr($self->attr)
    );

    $self->signature($parameters->signature) if ref $parameters;

    # IMHO multirefs should be encoded after Body, but only some
    # toolkits understand this encoding, so we'll keep them for now (04/15/2001)
    # as the last element inside the Body
    #                 v -------------- subelements of Envelope
    #                      vv -------- last of them (Body)
    #                            v --- subelements
    push(@{$encoded->[2]->[-1]->[2]}, $self->encode_multirefs) if ref $encoded->[2]->[-1]->[2];

    # Sometimes SOAP::Serializer is invoked statically when there is no context.
    # So first check to see if a context exists.
    # TODO - a context needs to be initialized by a constructor?
    if ($self->context && $self->context->packager->parts) {
        # TODO - this needs to be called! Calling it though wraps the payload twice!
        #  return $self->context->packager->package($self->xmlize($encoded));
    }

    return $self->xmlize($encoded);
}

1;

__END__