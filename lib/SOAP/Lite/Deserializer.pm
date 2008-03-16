package SOAP::Lite::Deserializer;

use strict;

use vars qw(@ISA);
use SOAP::Parser;
use SOAP::Lite::Utils;
use SOAP::Cloneable;
use URI;
@ISA = qw(SOAP::Cloneable);

sub DESTROY { SOAP::Trace::objects('()') }

sub BEGIN {
    __PACKAGE__->__mk_accessors( qw(ids hrefs parts parser
        base xmlschemas xmlschema context) );
}

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = $self;
    SOAP::Trace::objects('()');
    return bless {
        '_ids'        => {},
        '_hrefs'      => {},
        '_parser'     => SOAP::Parser->new,
        '_xmlschemas' => {
            $SOAP::Constants::NS_APS => 'SOAP::XMLSchemaApacheSOAP::Deserializer',
#            map {
#                $_ => $SOAP::Constants::XML_SCHEMAS{$_} . '::Deserializer'
#              } keys %SOAP::Constants::XML_SCHEMAS
            map {
                $_ => 'SOAP::Lite::Deserializer::' . $SOAP::Constants::XML_SCHEMA_OF{$_}
              } keys %SOAP::Constants::XML_SCHEMA_OF

        },
    }, $class;
}

sub is_xml {
    # Added check for envelope delivery. Fairly standard with MMDF and sendmail
    # Thanks to Chris Davies <Chris.Davies@ManheimEurope.com>
    $_[1] =~ /^\s*</ || $_[1] !~ /^(?:[\w-]+:|From )/;
}

sub baselocation {
    my $self = shift;
    my $location = shift;
    if ($location) {
        my $uri = URI->new($location);
        # make absolute location if relative
        $location = $uri->abs($self->base || 'thismessage:/')->as_string unless $uri->scheme;
    }
    return $location;
}

# Returns the envelope and populates SOAP::Packager with parts
sub decode_parts {
    my $self = shift;
    my $env = $self->context->packager->unpackage($_[0],$self->context);
    my $body = $self->parser->decode($env);
    # TODO - This shouldn't be here! This is packager specific!
    #        However this does need to pull out all the cid's
    #        to populate ids hash with.
    foreach (@{$self->context->packager->parts}) {
        my $data     = $_->bodyhandle->as_string;
        my $type     = $_->head->mime_attr('Content-Type');
        my $location = $_->head->mime_attr('Content-Location');
        my $id       = $_->head->mime_attr('Content-Id');
        $location = $self->baselocation($location);
        my $part = lc($type) eq 'text/xml' && !$SOAP::Constants::DO_NOT_PROCESS_XML_IN_MIME
            ? $self->parser->decode($data)
            : ['mimepart', {}, $data];
        # This below looks like unnecessary bloat!!!
        # I should probably dereference the mimepart, provide a callback to get the string data
        $id =~ s/^<([^>]*)>$/$1/; # string any leading and trailing brackets
        $self->ids->{$id} = $part if $id;
        $self->ids->{$location} = $part if $location;
    }
    return $body;
}

# decode returns a parsed body in the form of an ARRAY
# each element of the ARRAY is a HASH, ARRAY or SCALAR
sub decode {
    my $self = shift->new; # this actually is important
    return $self->is_xml($_[0])
        ? $self->parser->decode($_[0])
        : $self->decode_parts($_[0]);
}

# deserialize returns a SOAP::SOM object and parses straight
# text as input
sub deserialize {
    SOAP::Trace::trace('()');
    my $self = shift->new;

    # initialize
    $self->hrefs({});
    $self->ids({});

    # If the document is XML, then ids will be empty
    # If the document is MIME, then ids will hold a list of cids
    my $parsed = $self->decode($_[0]);

    # Having this code here makes multirefs in the Body work, but multirefs
    # that reference XML fragments in a MIME part do not work.
    if (keys %{$self->ids()}) {
        $self->traverse_ids($parsed);
    }
    else {
        # delay - set ids to be traversed later in decode_object, they only get
        # traversed if an href is found that is referencing an id.
        $self->ids($parsed);
    }
    $self->decode_object($parsed);
    my $som = SOAP::SOM->new($parsed);
    $som->context($self->context); # TODO - try removing this and see if it works!
    return $som;
}

sub traverse_ids {
    my $self = shift;
    my $ref = shift;
    my($undef, $attrs, $children) = @$ref;
    #  ^^^^^^ to fix nasty error on Mac platform (Carl K. Cunningham)
    $self->ids->{$attrs->{'id'}} = $ref if exists $attrs->{'id'};
    return unless ref $children;
    for (@$children) {
        $self->traverse_ids($_)
    };
}

use constant _ATTRS => 6;
use constant _NAME => 5;

sub decode_object {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;

    $ref->[ _ATTRS ] = $attrs = {%$attrs}; # make a copy for long attributes

    use vars qw(%uris);
    local %uris = (%uris, map {
        do { (my $ns = $_) =~ s/^xmlns:?//; $ns } => delete $attrs->{$_}
    } grep {/^xmlns(:|$)/} keys %$attrs);

    foreach (keys %$attrs) {
        next unless m/^($SOAP::Constants::NSMASK?):($SOAP::Constants::NSMASK)$/;

    $1 =~ /^[xX][mM][lL]/ ||
        $uris{$1} &&
            do {
                $attrs->{SOAP::Utils::longname($uris{$1}, $2)} = do {
                    my $value = $attrs->{$_};
                    $2 ne 'type' && $2 ne 'arrayType'
                        ? $value
                        : SOAP::Utils::longname($value =~ m/^($SOAP::Constants::NSMASK?):(${SOAP::Constants::NSMASK}(?:\[[\d,]*\])*)/
                            ? ($uris{$1} || die("Unresolved prefix '$1' for attribute value '$value'\n"), $2)
                            : ($uris{''} || die("Unspecified namespace for type '$value'\n"), $value)
                    );
                };
                1;
            }
            || die "Unresolved prefix '$1' for attribute '$_'\n";
  }

    # and now check the element
    my $ns = ($name =~ s/^($SOAP::Constants::NSMASK?):// ? $1 : '');
    $ref->[ _NAME ] = SOAP::Utils::longname(
        $ns
            ? ($uris{$ns} || die "Unresolved prefix '$ns' for element '$name'\n")
            : (defined $uris{''} ? $uris{''} : undef),
        $name
    );

    ($children, $value) = (undef, $children) unless ref $children;

    return $name => ($ref->[4] = $self->decode_value(
        [$ref->[ _NAME ], $attrs, $children, $value]
    ));
}

sub decode_value {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;

    # check SOAP version if applicable
    use vars '$level'; local $level = $level || 0;
    if (++$level == 1) {
        my($namespace, $envelope) = SOAP::Utils::splitlongname($name);
        SOAP::Lite->soapversion($namespace) if $envelope eq 'Envelope' && $namespace;
    }

    # check encodingStyle
    # future versions may bind deserializer to encodingStyle
    my $encodingStyle = $attrs->{"{$SOAP::Constants::NS_ENV}encodingStyle"} || "";
    my (%union,%isect);
    # TODO - SOAP 1.2 and 1.1 have different rules about valid encodingStyle values
    #        For example, in 1.1 - any http://schemas.xmlsoap.org/soap/encoding/*
    #        value is valid
    # Find intersection of declared and supported encoding styles
    foreach my $e (@SOAP::Constants::SUPPORTED_ENCODING_STYLES, split(/ +/,$encodingStyle)) {
        $union{$e}++ && $isect{$e}++;
    }
    die "Unrecognized/unsupported value of encodingStyle attribute '$encodingStyle'"
        if defined($encodingStyle) && length($encodingStyle) > 0 && !%isect &&
            !(SOAP::Lite->soapversion == 1.1 && $encodingStyle =~ /(?:^|\b)$SOAP::Constants::NS_ENC/);

    # removed to provide literal support in 0.65
    #$encodingStyle !~ /(?:^|\b)$SOAP::Constants::NS_ENC/;
    #                 # ^^^^^^^^ \b causing problems (!?) on some systems
    #                 # as reported by David Dyck <dcd@tc.fluke.com>
    #                 # so use (?:^|\b) instead

    use vars '$arraytype'; # type of Array element specified on Array itself
    # either specified with xsi:type, or <enc:name/> or array element
    my ($type) = grep { defined }
        map($attrs->{$_}, sort grep {/^\{$SOAP::Constants::NS_XSI_ALL\}type$/o} keys %$attrs),
           $name =~ /^\{$SOAP::Constants::NS_ENC\}/ ? $name : $arraytype;
    local $arraytype; # it's used only for one level, we don't need it anymore

    # $name is not used here since type should be encoded as type, not as name
    my ($schema, $class) = SOAP::Utils::splitlongname($type) if $type;
    my $schemaclass = defined($schema) && $self->xmlschemas->{$schema}
        || $self;

    {
        no strict qw(refs);
        if (! defined(%{"${schemaclass}::"}) ) {
            eval "require $schemaclass" or die $@ if not ref $schemaclass;
        }
    }

    # store schema that is used in parsed message
    $self->xmlschema($schema) if $schema && $schema =~ /XMLSchema/;

    # don't use class/type if anyType/ur-type is specified on wire
    undef $class
        if $schemaclass->can('anyTypeValue')
            && $schemaclass->anyTypeValue eq $class;

    my $method = 'as_' . ($class || '-'); # dummy type if not defined
    $class =~ s/__|\./::/g if $class;

    my $id = $attrs->{id};
    if (defined $id && exists $self->hrefs->{$id}) {
        return $self->hrefs->{$id};
    }
    elsif (exists $attrs->{href}) {
        (my $id = delete $attrs->{href}) =~ s/^(#|cid:|uuid:)?//;
        # convert to absolute if not internal '#' or 'cid:'
        $id = $self->baselocation($id) unless $1;
        return $self->hrefs->{$id} if exists $self->hrefs->{$id};
        # First time optimization. we don't traverse IDs unless asked for it.
        # This is where traversing id's is delayed from before
        #   - the first time through - ids should contain a copy of the parsed XML
        #     structure! seems silly to make so many copies
        my $ids = $self->ids;
        if (ref($ids) ne 'HASH') {
            $self->ids({});            # reset list of ids first time through
            $self->traverse_ids($ids);
        }
        if (exists($self->ids->{$id})) {
            my $obj = ($self->decode_object(delete($self->ids->{$id})))[1];
            return $self->hrefs->{$id} = $obj;
        }
        else {
            die "Unresolved (wrong?) href ($id) in element '$name'\n";
        }
    }

    return undef if grep {
        /^$SOAP::Constants::NS_XSI_NILS$/ && do {
            my $class = $self->xmlschemas->{ $1 || $2 };
            eval "require $class" or die @$;;
            $class->as_undef($attrs->{$_})
        }
    } keys %$attrs;

    # try to handle with typecasting
    my $res = $self->typecast($value, $name, $attrs, $children, $type);
    return $res if defined $res;

    # ok, continue with others
    if (exists $attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}) {
        my $res = [];
        $self->hrefs->{$id} = $res if defined $id;

        # check for arrayType which could be [1], [,2][5] or []
        # [,][1] will NOT be allowed right now (multidimensional sparse array)
        my($type, $multisize) = $attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}
            =~ /^(.+)\[(\d*(?:,\d+)*)\](?:\[(?:\d+(?:,\d+)*)\])*$/
                or die qq!Unrecognized/unsupported format of arrayType attribute '@{[$attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}]}'\n!;

        my @dimensions = map { $_ || undef } split /,/, $multisize;
        my $size = 1;
        foreach (@dimensions) { $size *= $_ || 0 }

        # TODO ähm, shouldn't this local be my?
        local $arraytype = $type;

        # multidimensional
        if ($multisize =~ /,/) {
            @$res = splitarray(
                [@dimensions],
                [map { scalar(($self->decode_object($_))[1]) } @{$children || []}]
            );
        }
        # normal
        else {
            @$res = map { scalar(($self->decode_object($_))[1]) } @{$children || []};
        }

        # sparse (position)
        if (ref $children && exists SOAP::Utils::o_lattr($children->[0])->{"{$SOAP::Constants::NS_ENC}position"}) {
            my @new;
            for (my $pos = 0; $pos < @$children; $pos++) {
                # TBD implement position in multidimensional array
                my($position) = SOAP::Utils::o_lattr($children->[$pos])->{"{$SOAP::Constants::NS_ENC}position"} =~ /^\[(\d+)\]$/
                    or die "Position must be specified for all elements of sparse array\n";
                $new[$position] = $res->[$pos];
            }
            @$res = @new;
        }

        # partially transmitted (offset)
        # TBD implement offset in multidimensional array
        my($offset) = $attrs->{"{$SOAP::Constants::NS_ENC}offset"} =~ /^\[(\d+)\]$/
            if exists $attrs->{"{$SOAP::Constants::NS_ENC}offset"};
        unshift(@$res, (undef) x $offset) if $offset;

        die "Too many elements in array. @{[scalar@$res]} instead of claimed $multisize ($size)\n"
            if $multisize && $size < @$res;

        # extend the array if number of elements is specified
        $#$res = $dimensions[0]-1 if defined $dimensions[0] && @$res < $dimensions[0];

        return defined $class && $class ne 'Array' ? bless($res => $class) : $res;

    }
    elsif ($name =~ /^\{$SOAP::Constants::NS_ENC\}Struct$/
        || !$schemaclass->can($method)
           && (ref $children || defined $class && $value =~ /^\s*$/)) {
        my $res = {};
        $self->hrefs->{$id} = $res if defined $id;

        # Patch code introduced in 0.65 - deserializes array properly
        # Decode each element of the struct.
        my %child_count_of = ();
        foreach my $child (@{$children || []}) {
            my ($child_name, $child_value) = $self->decode_object($child);
            # Store the decoded element in the struct.  If the element name is
            # repeated, replace the previous scalar value with a new array
            # containing both values.
            if (not $child_count_of{$child_name}) {
                # first time to see this value: use scalar
                $res->{$child_name} = $child_value;
            }
            elsif ($child_count_of{$child_name} == 1) {
                # second time to see this value: convert scalar to array
                $res->{$child_name} = [ $res->{$child_name}, $child_value ];
            }
            else {
                # already have an array: append to it
                push @{$res->{$child_name}}, $child_value;
            }
            $child_count_of{$child_name}++;
        }
        # End patch code

        return defined $class && $class ne 'SOAPStruct' ? bless($res => $class) : $res;
    }
    else {
        my $res;
        if (my $method_ref = $schemaclass->can($method)) {
            $res = $method_ref->($self, $value, $name, $attrs, $children, $type);
        }
        else {
            $res = $self->typecast($value, $name, $attrs, $children, $type);
            $res = $class ? die "Unrecognized type '$type'\n" : $value
                unless defined $res;
        }
        $self->hrefs->{$id} = $res if defined $id;
        return $res;
    }
}

sub splitarray {
    my @sizes = @{+shift};
    my $size = shift @sizes;
    my $array = shift;

    return splice(@$array, 0, $size) unless @sizes;
    my @array = ();
    push @array, [
        splitarray([@sizes], $array)
    ] while @$array && (!defined $size || $size--);
    return @array;
}

sub typecast { } # typecast is called for both objects AND scalar types
                 # check ref of the second parameter (first is the object)
                 # return undef if you don't want to handle it

1;

__END__