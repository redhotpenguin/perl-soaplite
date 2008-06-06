package SOAP::Lite::Server;

use strict;

use Carp ();
use SOAP::Lite::Deserializer;
use SOAP::Packager;
use SOAP::Serializer;
use SOAP::Transport;
use SOAP::Lite;

sub DESTROY { SOAP::Trace::objects('()') }

sub initialize {
    return (
        packager => SOAP::Packager::MIME->new,
        transport => SOAP::Transport->new,
        serializer => SOAP::Serializer->new,
        deserializer => SOAP::Lite::Deserializer->new,
        on_action => sub { ; },
        on_dispatch => sub {
            return;
        },
    );
}

sub new {
    my $self = shift;
    return $self if ref $self;

    unless (ref $self) {
        my $class = $self;
        my(@params, @methods);

        while (@_) {
            my($method, $params) = splice(@_,0,2);
            $class->can($method)
                ? push(@methods, $method, $params)
                : $^W && Carp::carp "Unrecognized parameter '$method' in new()";
        }

        $self = bless {
            _dispatch_to   => [],
            _dispatch_with => {},
            _dispatched    => [],
            _action        => '',
            _options       => {},
        } => $class;
        unshift(@methods, $self->initialize);
        no strict qw(refs);
        while (@methods) {
            my($method, $params) = splice(@methods,0,2);
            $self->$method(ref $params eq 'ARRAY' ? @$params : $params)
        }
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()"
        if $^W && (@_ & 1);

    no strict qw(refs);
    while (@_) {
        my($method, $params) = splice(@_,0,2);
        $self->can($method)
            ? $self->$method(ref $params eq 'ARRAY' ? @$params : $params)
            : $^W && Carp::carp "Unrecognized parameter '$method' in new()"
    }

    return $self;
}

sub init_context {
    my $self = shift;
    $self->{'_deserializer'}->{'_context'} = $self;
    $self->{'_serializer'}->{'_context'} = $self;
}

sub destroy_context {
    my $self = shift;
    delete($self->{'_deserializer'}->{'_context'});
    delete($self->{'_serializer'}->{'_context'})
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(serializer deserializer transport)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new();
            if (@_) {
                my $context = $self->{$field}->{'_context'}; # save the old context
                $self->{$field} = shift;
                $self->{$field}->{'_context'} = $context;    # restore the old context
                return $self;
            }
            else {
                return $self->{$field};
            }
        }
    }

    for my $method (qw(action myuri options dispatch_with packager)) {
    my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new();
            (@_)
                ? do {
                    $self->{$field} = shift;
                    return $self;
                }
                : return $self->{$field};
        }
    }
    for my $method (qw(on_action on_dispatch)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            # my $self = shift;
            return $self->{$field} unless @_;
            local $@;
            # commented out because that 'eval' was unsecure
            # > ref $_[0] eq 'CODE' ? shift : eval shift;
            # Am I paranoid enough?
            $self->{$field} = shift;
            Carp::croak $@ if $@;
            Carp::croak "$method() expects subroutine (CODE) or string that evaluates into subroutine (CODE)"
                unless ref $self->{$field} eq 'CODE';
            return $self;
        }
    }

    #    __PACKAGE__->__mk_accessors( qw(dispatch_to) );
    for my $method (qw(dispatch_to)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            # my $self = shift;
            (@_)
                ? do {
                    $self->{$field} = [@_];
                    return $self;
                }
                : return @{ $self->{$field} };
        }
    }
}

sub objects_by_reference {
    my $self = shift;
    $self = $self->new() if not ref $self;
    @_
        ? (SOAP::Server::Object->objects_by_reference(@_), return $self)
        : SOAP::Server::Object->objects_by_reference;
}

sub dispatched {
    my $self = shift;
    $self = $self->new() if not ref $self;
    @_
        ? (push(@{$self->{_dispatched}}, @_), return $self)
        : return @{$self->{_dispatched}};
}

sub find_target {
    my $self = shift;
    my $request = shift;

    # try to find URI/method from on_dispatch call first
    my($method_uri, $method_name) = $self->on_dispatch->($request);

    # if nothing there, then get it from envelope itself
    $request->match((ref $request)->method);
    ($method_uri, $method_name) = ($request->namespaceuriof || '', $request->dataof->name)
        unless $method_name;

    $self->on_action->(my $action = $self->action, $method_uri, $method_name);

    # check to avoid security vulnerability: Protected->Unprotected::method(@parameters)
    # see for more details: http://www.phrack.org/phrack/58/p58-0x09
    die "Denied access to method ($method_name)\n" unless $method_name =~ /^\w+$/;

    my ($class, $static);
    # try to bind directly
    if (defined($class = $self->dispatch_with->{$method_uri}
            || $self->dispatch_with->{$action || ''}
            || ($action =~ /^"(.+)"$/
                ? $self->dispatch_with->{$1}
                : undef))) {
        # return object, nothing else to do here
        return ($class, $method_uri, $method_name) if ref $class;
        $static = 1;
    }
    else {
        die "URI path shall map to class" unless defined ($class = URI->new($method_uri)->path);

        for ($class) { s!^/|/$!!g; s!/!::!g; s/^$/main/; }
        die "Failed to access class ($class)" unless $class =~ /^(\w[\w:]*)$/;

        my $fullname = "$class\::$method_name";
        foreach ($self->dispatch_to) {
            return ($_, $method_uri, $method_name) if ref eq $class; # $OBJECT
            next if ref;                                   # skip other objects
            # will ignore errors, because it may complain on
            # d:\foo\bar, which is PATH and not regexp
            eval {
                $static ||= $class =~ /^$_$/           # MODULE
                    || $fullname =~ /^$_$/             # MODULE::method
                    || $method_name =~ /^$_$/ && ($class eq 'main'); # method ('main' assumed)
            };
        }
    }

    no strict 'refs';

# TODO - sort this mess out:
# The task is to test whether the class in question has already been loaded.
#
# SOAP::Lite 0.60:
#  unless (defined %{"${class}::"}) {
# Patch to SOAP::Lite 0.60:
# The following patch does not work for packages defined within a BEGIN block
#  unless (exists($INC{join '/', split /::/, $class.'.pm'})) {
# Combination of 0.60 and patch did not work reliably, either.
#
# Now we do the following: Check whether the class is main (always loaded)
# or the class implements the method in question
# or the package exists as file in %INC.
#
# This is still sort of a hack - but I don't know anything better
# If you have some idea, please help me out...
#
    unless (($class eq 'main') || $class->can($method_name)
        || exists($INC{join '/', split /::/, $class . '.pm'})) {

        # allow all for static and only specified path for dynamic bindings
        local @INC = (($static ? @INC : ()), grep {!ref && m![/\\.]!} $self->dispatch_to());
        eval 'local $^W; ' . "require $class";
        die "Failed to access class ($class): $@" if $@;
        $self->dispatched($class) unless $static;
    }

    die "Denied access to method ($method_name) in class ($class)"
        unless $static || grep {/^$class$/} $self->dispatched;

    return ($class, $method_uri, $method_name);
}


sub handle {
    SOAP::Trace::trace('()');
    my $self = shift;
    $self = $self->new if !ref $self; # inits the server when called in a static context
    $self->init_context();
    # we want to restore it when we are done
    local $SOAP::Constants::DEFAULT_XML_SCHEMA
        = $SOAP::Constants::DEFAULT_XML_SCHEMA;

    # SOAP version WILL NOT be restored when we are done.
    # is it problem?

    my $result = eval {
        local $SIG{__DIE__};
        # why is this here:
        $self->serializer->soapversion(1.1);
        my $request = eval { $self->deserializer->deserialize($_[0]) };

        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_VERSION_MISMATCH)
            ->faultstring($@)
                if $@ && $@ =~ /^$SOAP::Constants::WRONG_VERSION/;

        die "Application failed during request deserialization: $@" if $@;
        my $som = ref $request;
        die "Can't find root element in the message"
            unless $request->match($som->envelope);
        $self->serializer->soapversion(SOAP::Lite->soapversion);
        $self->serializer->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA
            = $self->deserializer->xmlschema)
                if $self->deserializer->xmlschema;

        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_MUST_UNDERSTAND)
            ->faultstring("Unrecognized header has mustUnderstand attribute set to 'true'")
            if !$SOAP::Constants::DO_NOT_CHECK_MUSTUNDERSTAND &&
                grep {
                    $_->mustUnderstand
                    && (!$_->actor || $_->actor eq $SOAP::Constants::NEXT_ACTOR)
                } $request->dataof($som->headers);

        die "Can't find method element in the message"
            unless $request->match($som->method);
        # TODO - SOAP::Dispatcher plugs in here
        # my $handler = $self->dispatcher->find_handler($request);
        my($class, $method_uri, $method_name) = $self->find_target($request);
        my @results = eval {
            local $^W;
            my @parameters = $request->paramsin;

            # SOAP::Trace::dispatch($fullname);
            SOAP::Trace::parameters(@parameters);

            push @parameters, $request
                if UNIVERSAL::isa($class => 'SOAP::Server::Parameters');

            no strict qw(refs);
            SOAP::Server::Object->references(
                defined $parameters[0]
                && ref $parameters[0]
                && UNIVERSAL::isa($parameters[0] => $class)
                    ? do {
                        my $object = shift @parameters;
                        SOAP::Server::Object->object(ref $class
                            ? $class
                            : $object
                        )->$method_name(SOAP::Server::Object->objects(@parameters)),

                        # send object back as a header
                        # preserve name, specify URI
                        SOAP::Header
                            ->uri($SOAP::Constants::NS_SL_HEADER => $object)
                            ->name($request->dataof($som->method.'/[1]')->name)
                    } # end do block

                    # SOAP::Dispatcher will plug-in here as well
                    # $handler->dispatch(SOAP::Server::Object->objects(@parameters)
                    : $class->$method_name(SOAP::Server::Object->objects(@parameters)) );
        }; # end eval block
        SOAP::Trace::result(@results);

        # let application errors pass through with 'Server' code
        die ref $@
            ? $@
            : $@ =~ /^Can\'t locate object method "$method_name"/
                ? "Failed to locate method ($method_name) in class ($class)"
                : SOAP::Fault->faultcode($SOAP::Constants::FAULT_SERVER)->faultstring($@)
                    if $@;

        my $result = $self->serializer
            ->prefix('s') # distinguish generated element names between client and server
            ->uri($method_uri)
            ->envelope(response => $method_name . 'Response', @results);
        $self->destroy_context();
        return $result;
    };

    $self->destroy_context();
    # void context
    return unless defined wantarray;

    # normal result
    return $result unless $@;

    # check fails, something wrong with message
    return $self->make_fault($SOAP::Constants::FAULT_CLIENT, $@) unless ref $@;

    # died with SOAP::Fault
    return $self->make_fault($@->faultcode   || $SOAP::Constants::FAULT_SERVER,
        $@->faultstring || 'Application error',
        $@->faultdetail, $@->faultactor)
    if UNIVERSAL::isa($@ => 'SOAP::Fault');

    # died with complex detail
    return $self->make_fault($SOAP::Constants::FAULT_SERVER, 'Application error' => $@);

} # end of handle()

sub make_fault {
    my $self = shift;
    my($code, $string, $detail, $actor) = @_;
    $self->serializer->fault($code, $string, $detail, $actor || $self->myuri);
}


1;

__END__