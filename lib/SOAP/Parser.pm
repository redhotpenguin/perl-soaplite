package SOAP::Parser;

use strict;

sub DESTROY { SOAP::Trace::objects('()') }

sub xmlparser {
    my $self = shift;
    return eval {
        $SOAP::Constants::DO_NOT_USE_XML_PARSER
            ? undef
            : do {
                require XML::Parser;
                XML::Parser->new() }
            }
            || eval { require XML::Parser::Lite; XML::Parser::Lite->new }
            || die "XML::Parser is not @{[$SOAP::Constants::DO_NOT_USE_XML_PARSER ? 'used' : 'available']} and ", $@;
}

sub parser {
    my $self = shift->new;
    @_
        ? do {
            $self->{'_parser'} = shift;
            return $self;
        }
        : return ($self->{'_parser'} ||= $self->xmlparser);
}

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = $self;
    SOAP::Trace::objects('()');
    return bless {_parser => shift}, $class;
}

sub decode { SOAP::Trace::trace('()');
    my $self = shift;

    $self->parser->setHandlers(
        Final => sub { shift; $self->final(@_) },
        Start => sub { shift; $self->start(@_) },
        End   => sub { shift; $self->end(@_)   },
        Char  => sub { shift; $self->char(@_)  },
        ExternEnt => sub { shift; die "External entity (pointing to '$_[1]') is not allowed" },
    );
    # my $parsed = $self->parser->parse($_[0]);
    # return $parsed;
    #
    my $ret = undef;
    eval {
        $ret = $self->parser->parse($_[0]);
    };
    if ($@) {
        $self->final; # Clean up in the event of an error
        die $@; # Pass back the error
    }
    return $ret;
}

sub final {
    my $self = shift;

    # clean handlers, otherwise SOAP::Parser won't be deleted:
    # it refers to XML::Parser which refers to subs from SOAP::Parser
    # Thanks to Ryan Adams <iceman@mit.edu>
    # and Craig Johnston <craig.johnston@pressplay.com>
    # checked by number of tests in t/02-payload.t

    undef $self->{_values};
    $self->parser->setHandlers(
        Final => undef,
        Start => undef,
        End => undef,
        Char => undef,
        ExternEnt => undef,
    );
    $self->{_done};
}

sub start { push @{shift->{_values}}, [shift, {@_}] }

# string concatenation changed to arrays which should improve performance
# for strings with many entity-encoded elements.
# Thanks to Mathieu Longtin <mrdamnfrenchy@yahoo.com>
sub char { push @{shift->{_values}->[-1]->[3]}, shift }

sub end {
    my $self = shift;
    my $done = pop @{$self->{_values}};
    $done->[2] = defined $done->[3]
        ? join('',@{$done->[3]})
        : '' unless ref $done->[2];
    undef $done->[3];
    @{$self->{_values}}
        ? (push @{$self->{_values}->[-1]->[2]}, $done)
        : ($self->{_done} = $done);
}

1;

__END__