package SOAP::Lite;

# ======================================================================
#
# Copyright (C) 2000-2005 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

# Formatting hint:
# Target is the source code format laid out in Perl Best Practices (4 spaces
# indent, opening brace on condition line, no cuddled else).
#
# October 2007, Martin Kutter

use 5.005;
use strict;
use vars qw($AUTOLOAD @ISA $VERSION);
use Carp ();

use version; $VERSION = qv('0.71.03');

use SOAP::Lite::Utils;
use SOAP::Constants;
use SOAP::Packager;
use SOAP::SOM;
use SOAP::Transport;
use SOAP::Lite::Serializer;
use SOAP::Schema::WSDL;
use SOAP::Lite::Deserializer;

use Scalar::Util qw(weaken);

@ISA = qw(SOAP::Cloneable);

# provide access to global/autodispatched object
sub self {
    @_ > 1
        ? $SOAP::soap = $_[1]
        : $SOAP::soap
}

# no more warnings about "used only once"
*UNIVERSAL::AUTOLOAD if 0;

sub autodispatched { \&{*UNIVERSAL::AUTOLOAD} eq \&{*SOAP::AUTOLOAD} };

sub soapversion {
    my $self = shift;
    my $version = shift or return $SOAP::Constants::SOAP_VERSION;

    ($version) = grep {
        $SOAP::Constants::SOAP_VERSIONS{$_}->{NS_ENV} eq $version
        } keys %SOAP::Constants::SOAP_VERSIONS
            unless exists $SOAP::Constants::SOAP_VERSIONS{$version};

    die qq!$SOAP::Constants::WRONG_VERSION Supported versions:\n@{[
        join "\n", map {"  $_ ($SOAP::Constants::SOAP_VERSIONS{$_}->{NS_ENV})"} keys %SOAP::Constants::SOAP_VERSIONS
        ]}\n!
        unless defined($version) && defined(my $def = $SOAP::Constants::SOAP_VERSIONS{$version});

    foreach (keys %$def) {
        eval "\$SOAP::Constants::$_ = '$SOAP::Constants::SOAP_VERSIONS{$version}->{$_}'";
    }

    $SOAP::Constants::SOAP_VERSION = $version;

    return $self;
}

BEGIN { SOAP::Lite->soapversion(1.1) }

sub import {
    my $pkg = shift;
    my $caller = caller;
    no strict 'refs';
    # emulate 'use SOAP::Lite 0.99' behavior
    $pkg->require_version(shift) if defined $_[0] && $_[0] =~ /^\d/;

    while (@_) {
        my $command = shift;

        my @parameters = UNIVERSAL::isa($_[0] => 'ARRAY')
            ? @{shift()}
            : shift
                if @_ && $command ne 'autodispatch';

        if ($command eq 'autodispatch' || $command eq 'dispatch_from') {
            $SOAP::soap = ($SOAP::soap||$pkg)->new;
            no strict 'refs';
            foreach ($command eq 'autodispatch'
                ? 'UNIVERSAL'
                : @parameters
            ) {
                my $sub = "${_}::AUTOLOAD";
                defined &{*$sub}
                    ? (\&{*$sub} eq \&{*SOAP::AUTOLOAD}
                        ? ()
                        : Carp::croak "$sub already assigned and won't work with DISPATCH. Died")
                    : (*$sub = *SOAP::AUTOLOAD);
            }
        }
        elsif ($command eq 'service') {
            foreach (keys %{SOAP::Schema->schema_url(shift(@parameters))->parse(@parameters)->load->services}) {
                $_->export_to_level(1, undef, ':all');
            }
        }
        elsif ($command eq 'debug' || $command eq 'trace') {
            SOAP::Trace->import(@parameters ? @parameters : 'all');
        }
        elsif ($command eq 'import') {
            local $^W; # supress warnings about redefining
            my $package = shift(@parameters);
            $package->export_to_level(1, undef, @parameters ? @parameters : ':all') if $package;
        }
        else {
            Carp::carp "Odd (wrong?) number of parameters in import(), still continue" if $^W && !(@parameters & 1);
            $SOAP::soap = ($SOAP::soap||$pkg)->$command(@parameters);
        }
    }
}

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;
    unless (ref $self) {
        my $class = $self;
        # Check whether we can clone. Only the SAME class allowed, no inheritance
        $self = ref($SOAP::soap) eq $class ? $SOAP::soap->clone : {
            _transport    => SOAP::Transport->new,
            _serializer   => SOAP::Serializer->new,
            _deserializer => SOAP::Lite::Deserializer->new,
            _packager     => SOAP::Packager::MIME->new,
            _schema       => undef,
            _autoresult   => 0,
            _on_action    => sub { sprintf '"%s#%s"', shift || '', shift },
            _on_fault     => sub {ref $_[1] ? return $_[1] : Carp::croak $_[0]->transport->is_success ? $_[1] : $_[0]->transport->status},
        };
        bless $self => $class;
        $self->on_nonserialized($self->on_nonserialized || $self->serializer->on_nonserialized);
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
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
    # weaken circular reference to avoid a memory hole
    weaken($self->{'_deserializer'}->{'_context'});

    $self->{'_serializer'}->{'_context'} = $self;
    # weaken circular reference to avoid a memory hole
    weaken($self->{'_serializer'}->{'_context'});
}


# Naming? wsdl_parser
sub schema {
    my $self = shift;
    if (@_) {
        $self->{'_schema'} = shift;
        return $self;
    }
    else {
        if (!defined $self->{'_schema'}) {
            $self->{'_schema'} = SOAP::Schema->new;
        }
        return $self->{'_schema'};
    }
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(serializer deserializer)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
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

    __PACKAGE__->__mk_accessors(
        qw(endpoint transport outputxml autoresult packager)
    );
    #  for my $method () {
    #    my $field = '_' . $method;
    #    *$method = sub {
    #      my $self = shift->new;
    #      @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
    #    }
    #  }
    for my $method (qw(on_action on_fault on_nonserialized)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
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
    # SOAP::Transport Shortcuts
    # TODO - deprecate proxy() in favor of new language endpoint_url()
    no strict qw(refs);
    for my $method (qw(proxy)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->transport->$method(@_), return $self) : return $self->transport->$method();
        }
    }

    # SOAP::Seriailizer Shortcuts
    for my $method (qw(autotype readable envprefix encodingStyle
                    encprefix multirefinplace encoding
                    typelookup header maptype xmlschema
                    uri ns_prefix ns_uri use_prefix use_default_ns
                    ns default_ns)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->serializer->$method(@_), return $self) : return $self->serializer->$method();
        }
    }

    # SOAP::Schema Shortcuts
    for my $method (qw(cache_dir cache_ttl)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->schema->$method(@_), return $self) : return $self->schema->$method();
        }
    }
}

sub parts {
    my $self = shift;
    $self->packager->parts(@_);
    return $self;
}

# Naming? wsdl
sub service {
    my $self = shift->new;
    return $self->{'_service'} unless @_;
    $self->schema->schema_url($self->{'_service'} = shift);
    my %services = %{$self->schema->parse(@_)->load->services};

    Carp::croak "More than one service in service description. Service and port names have to be specified\n"
        if keys %services > 1;
    my $service = (keys %services)[0]->new;
    return $service;
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    ref $_[0] or Carp::croak qq!Can\'t locate class method "$method" via package \"! . __PACKAGE__ .'\"';

    no strict 'refs';
    *$AUTOLOAD = sub {
        my $self = shift;
        my $som = $self->call($method => @_);
        return $self->autoresult && UNIVERSAL::isa($som => 'SOAP::SOM')
            ? wantarray ? $som->paramsall : $som->result
            : $som;
    };
    goto &$AUTOLOAD;
}

sub call {
    SOAP::Trace::trace('()');
    my $self = shift;

    die "A service address has not been specified either by using SOAP::Lite->proxy() or a service description)\n"
        unless defined $self->proxy && UNIVERSAL::isa($self->proxy => 'SOAP::Client');

    $self->init_context();

    my $serializer = $self->serializer();
    $serializer->on_nonserialized( $self->on_nonserialized() );

    my $response = $self->transport()->send_receive(
        context  => $self, # this is provided for context
        endpoint => $self->endpoint(),
        action   => scalar($self->on_action->($serializer->uriformethod($_[0]))),
                # leave only parameters so we can later update them if required
        envelope => $serializer->envelope(method => shift, @_),
        encoding => $serializer->encoding(),
        parts    => @{$self->packager->parts} ? $self->packager()->parts() : undef,
    );

    return $response if $self->outputxml();

    my $result = eval { $self->deserializer()->deserialize($response) }
        if $response;

    if (!$self->transport()->is_success() || # transport fault
        $@ ||                            # not deserializible
        # fault message even if transport OK
        # or no transport error (for example, fo TCP, POP3, IO implementations)
        UNIVERSAL::isa($result => 'SOAP::SOM') && $result->fault) {
        return ($self->on_fault->($self, $@
            ? $@ . ($response || '')
            : $result)
                || $result
        );
        # ? # trick editors
    }
    # this might be trouble for connection close...
    return unless $response; # nothing to do for one-ways

    # little bit tricky part that binds in/out parameters
    if (UNIVERSAL::isa($result => 'SOAP::SOM')
        && ($result->paramsout || $result->headers)
        && $serializer->signature) {
        my $num = 0;
        my %signatures = map {$_ => $num++} @{$serializer->signature};
        for ($result->dataof(SOAP::SOM::paramsout), $result->dataof(SOAP::SOM::headers)) {
            my $signature = join $;, $_->name, $_->type || '';
            if (exists $signatures{$signature}) {
    	        my $param = $signatures{$signature};
    	        my($value) = $_->value; # take first value

                # fillup parameters
                UNIVERSAL::isa($_[$param] => 'SOAP::Data')
                    ? $_[$param]->SOAP::Data::value($value)
                    : UNIVERSAL::isa($_[$param] => 'ARRAY')
                        ? (@{$_[$param]} = @$value)
                        : UNIVERSAL::isa($_[$param] => 'HASH')
                            ? (%{$_[$param]} = %$value)
                            : UNIVERSAL::isa($_[$param] => 'SCALAR')
                                ? (${$_[$param]} = $$value)
                                : ($_[$param] = $value)
            }
        }
    }
    return $result;
} # end of call()

1;

package SOAP;

use strict;

use vars qw($AUTOLOAD);
require URI;

our $soap; # shared between SOAP and SOAP::Lite packages

{
    no strict 'refs';
    *AUTOLOAD = sub {
        local($1,$2);
        my($package, $method) = $AUTOLOAD =~ m/(?:(.+)::)([^:]+)$/;
        return if $method eq 'DESTROY';

        my $soap = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $_[0]
            : $soap
                || die "SOAP:: prefix shall only be used in combination with +autodispatch option\n";

        my $uri = URI->new($soap->uri);
        my $currenturi = $uri->path;
        $package = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $currenturi
            : $package eq 'SOAP'
                ? ref $_[0] || ($_[0] eq 'SOAP'
                    ? $currenturi || Carp::croak "URI is not specified for method call"
                    : $_[0])
                : $package eq 'main'
                    ? $currenturi || $package
                    : $package;

        # drop first parameter if it's a class name
        {
            my $pack = $package;
            for ($pack) { s!^/!!; s!/!::!g; }
            shift @_ if @_ && !ref $_[0] && ($_[0] eq $pack || $_[0] eq 'SOAP')
                || ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite');
        }

        for ($package) { s!::!/!g; s!^/?!/!; }
        $uri->path($package);

        my $som = $soap->uri($uri->as_string)->call($method => @_);
        UNIVERSAL::isa($som => 'SOAP::SOM')
            ? wantarray
                ? $som->paramsall
                : $som->result
            : $som;
    };
}

1;

__END__

=pod

=head1 NAME

SOAP::Lite - Perl's Web Services Toolkit

=head1 DESCRIPTION

SOAP::Lite is a collection of Perl modules which provides a simple and
lightweight interface to the Simple Object Access Protocol (SOAP) both on
client and server side.

=head1 PERL VERSION WARNING

SOAP::Lite 0.71 will be the last version of SOAP::Lite running on perl 5.005

Future versions of SOAP::Lite will require at least perl 5.6.0

If you have not had the time to upgrade your perl, you should consider this
now.

=head1 OVERVIEW OF CLASSES AND PACKAGES

=over

=item F<lib/SOAP/Lite.pm>

L<SOAP::Lite> - Main class provides all logic

L<SOAP::Transport> - Transport backend

L<SOAP::Data> - Data objects

L<SOAP::Header> - Header Data Objects

L<SOAP::Serializer> - Serializes data structures to SOAP messages

L<SOAP::Lite::Deserializer> - Deserializes SOAP messages into SOAP::SOM objects

L<SOAP::SOM> - SOAP Message objects

L<SOAP::Constants> - Provides access to common constants and defaults

L<SOAP::Trace> - Tracing facilities

L<SOAP::Schema> - Provides access and stub(s) for schema(s)

L<SOAP::Schema::WSDL|SOAP::Schema/SOAP::Schema::WSDL> - WSDL implementation for SOAP::Schema

L<SOAP::Server> - Handles requests on server side

SOAP::Server::Object - Handles objects-by-reference

L<SOAP::Fault> - Provides support for Faults on server side

L<SOAP::Utils> - A set of private and public utility subroutines

=item F<lib/SOAP/Packager.pm>

L<SOAP::Packager> - Provides an abstract class for implementing custom packagers.

L<SOAP::Packager::MIME|SOAP::Packager/SOAP::Packager::MIME> - Provides MIME support to SOAP::Lite

L<SOAP::Packager::DIME|SOAP::Packager/SOAP::Packager::DIME> - Provides DIME support to SOAP::Lite

=item F<lib/SOAP/Transport/HTTP.pm>

L<SOAP::Transport::HTTP::Client|SOAP::Transport/SOAP::Transport::HTTP::Client> - Client interface to HTTP transport

L<SOAP::Transport::HTTP::Server|SOAP::Transport/SOAP::Transport::HTTP::Server> - Server interface to HTTP transport

L<SOAP::Transport::HTTP::CGI|SOAP::Transport/SOAP::Transport::HTTP::CGI> - CGI implementation of server interface

L<SOAP::Transport::HTTP::Daemon|SOAP::Transport/SOAP::Transport::HTTP::Daemon> - Daemon implementation of server interface

L<SOAP::Transport::HTTP::Apache|SOAP::Transport/SOAP::Transport::HTTP::Apache> - mod_perl implementation of server interface

=item F<lib/SOAP/Transport/POP3.pm>

L<SOAP::Transport::POP3::Server|SOAP::Transport/SOAP::Transport::POP3::Server> - Server interface to POP3 protocol

=item F<lib/SOAP/Transport/MAILTO.pm>

L<SOAP::Transport::MAILTO::Client|SOAP::Transport/SOAP::Transport::MAILTO::Client> - Client interface to SMTP/sendmail

=item F<lib/SOAP/Transport/LOCAL.pm>

L<SOAP::Transport::LOCAL::Client|SOAP::Transport/SOAP::Transport::LOCAL::Client> - Client interface to local transport

=item F<lib/SOAP/Transport/TCP.pm>

L<SOAP::Transport::TCP::Server|SOAP::Transport/SOAP::Transport::TCP::Server> - Server interface to TCP protocol

L<SOAP::Transport::TCP::Client|SOAP::Transport/SOAP::Transport::TCP::Client> - Client interface to TCP protocol

=item F<lib/SOAP/Transport/IO.pm>

L<SOAP::Transport::IO::Server|SOAP::Transport/SOAP::Transport::IO::Server> - Server interface to IO transport

=back

=head1 METHODS

All accessor methods return the current value when called with no arguments,
while returning the object reference itself when called with a new value.
This allows the set-attribute calls to be chained together.

=over

=item new(optional key/value pairs)

    $client = SOAP::Lite->new(proxy => $endpoint)

Constructor. Many of the accessor methods defined here may be initialized at
creation by providing their name as a key, followed by the desired value.
The example provides the value for the proxy element of the client.

=item transport(optional transport object)

    $transp = $client->transport( );

Gets or sets the transport object used for sending/receiving SOAP messages.

See L<SOAP::Transport> for details.

=item serializer(optional serializer object)

    $serial = $client->serializer( )

Gets or sets the serializer object used for creating XML messages.

See L<SOAP::Serializer> for details.

=item packager(optional packager object)

    $packager = $client->packager( )

Provides access to the C<SOAP::Packager> object that the client uses to manage
the use of attachments. The default packager is a MIME packager, but unless
you specify parts to send, no MIME formatting will be done.

See also: L<SOAP::Packager>.

=item proxy(endpoint, optional extra arguments)

    $client->proxy('http://soap.xml.info/ endPoint');

The proxy is the server or endpoint to which the client is going to connect.
This method allows the setting of the endpoint, along with any extra
information that the transport object may need when communicating the request.

This method is actually an alias to the proxy method of L<SOAP::Transport>.
It is the same as typing:

    $client->transport( )->proxy(...arguments);

Extra parameters can be passed to proxy() - see below.

=over

=item compress_threshold

See L<COMPRESSION|SOAP::Transport/"COMPRESSION"> in L<HTTP::Transport>.

=item All initialization options from the underlying transport layer

The options for HTTP(S) are the same as for LWP::UserAgent's new() method.

A common option is to create a instance of HTTP::Cookies and pass it as
cookie_jar option:

 my $cookie_jar = HTTP::Cookies->new()
 $client->proxy('http://www.example.org/webservice',
    cookie_jar => $cookie_jar,
 );

=back

For example, if you wish to set the HTTP timeout for a SOAP::Lite client to 5
seconds, use the following code:

  my $soap = SOAP::Lite
   ->uri($uri)
   ->proxy($proxyUrl, timeout => 5 );

See L<LWP::UserAgent>.

=item endpoint(optional new endpoint address)

    $client->endpoint('http://soap.xml.info/ newPoint')

It may be preferable to set a new endpoint without the additional work of
examining the new address for protocol information and checking to ensure the
support code is loaded and available. This method allows the caller to change
the endpoint that the client is currently set to connect to, without
reloading the relevant transport code. Note that the proxy method must have
been called before this method is used.

=item service(service URL)

    $client->service('http://svc.perl.org/Svc.wsdl');

C<SOAP::Lite> offers some support for creating method stubs from service
descriptions. At present, only WSDL support is in place. This method loads
the specified WSDL schema and uses it as the basis for generating stubs.

=item outputxml(boolean)

    $client->outputxml('true');

When set to a true value, the raw XML is returned by the call to a remote
method.

The default is to return the a L<SOAP::SOM> object (false).

=item autotype(boolean)

    $client->autotype(0);

This method is a shortcut for:

    $client->serializer->autotype(boolean);

By default, the serializer tries to automatically deduce types for the data
being sent in a message. Setting a false value with this method disables the
behavior.

=item readable(boolean)

    $client->readable(1);

This method is a shortcut for:

    $client->serializer->readable(boolean);

When this is used to set a true value for this property, the generated XML
sent to the endpoint has extra characters (spaces and new lines) added in to
make the XML itself more readable to human eyes (presumably for debugging).
The default is to not send any additional characters.

=item default_ns($uri)

Sets the default namespace for the request to the specified uri. This
overrides any previous namespace declaration that may have been set using a
previous call to C<ns()> or C<default_ns()>. Setting the default namespace
causes elements to be serialized without a namespace prefix, like this:

  <soap:Envelope>
    <soap:Body>
      <myMethod xmlns="http://www.someuri.com">
        <foo />
      </myMethod>
    </soap:Body>
  </soap:Envelope>

Some .NET web services have been reported to require this XML namespace idiom.

=item ns($uri,$prefix=undef)

Sets the namespace uri and optionally the namespace prefix for the request to
the specified values. This overrides any previous namespace declaration that
may have been set using a previous call to C<ns()> or C<default_ns()>.

If a prefix is not specified, one will be generated for you automatically.
Setting the namespace causes elements to be serialized with a declared
namespace prefix, like this:

  <soap:Envelope>
    <soap:Body>
      <my:myMethod xmlns:my="http://www.someuri.com">
        <my:foo />
      </my:myMethod>
    </soap:Body>
  </soap:Envelope>

=item use_prefix(boolean)

Deprecated. Use the C<ns()> and C<default_ns> methods described above.

Shortcut for C<< serializer->use_prefix() >>. This lets you turn on/off the
use of a namespace prefix for the children of the /Envelope/Body element.
Default is 'true'.

When use_prefix is set to 'true', serialized XML will look like this:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <namesp1:mymethod xmlns:namesp1="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

When use_prefix is set to 'false', serialized XML will look like this:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <mymethod xmlns="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

Some .NET web services have been reported to require this XML namespace idiom.

=item soapversion(optional value)

    $client->soapversion('1.2');

If no parameter is given, returns the current version of SOAP that is being
used by the client object to encode requests. If a parameter is given, the
method attempts to set that as the version of SOAP being used.

The value should be either 1.1 or 1.2.

=item envprefix(QName)

    $client->envprefix('env');

This method is a shortcut for:

    $client->serializer->envprefix(QName);

Gets or sets the namespace prefix for the SOAP namespace. The default is
SOAP.

The prefix itself has no meaning, but applications may wish to chose one
explicitly to denote different versions of SOAP or the like.

=item encprefix(QName)

    $client->encprefix('enc');

This method is a shortcut for:

    $client->serializer->encprefix(QName);

Gets or sets the namespace prefix for the encoding rules namespace.
The default value is SOAP-ENC.

=back

While it may seem to be an unnecessary operation to set a value that isn't
relevant to the message, such as the namespace labels for the envelope and
encoding URNs, the ability to set these labels explicitly can prove to be a
great aid in distinguishing and debugging messages on the server side of
operations.

=over

=item encoding(encoding URN)

    $client->encoding($soap_12_encoding_URN);

This method is a shortcut for:

    $client->serializer->encoding(args);

Where the earlier method dealt with the label used for the attributes related
to the SOAP encoding scheme, this method actually sets the URN to be specified
as the encoding scheme for the message. The default is to specify the encoding
for SOAP 1.1, so this is handy for applications that need to encode according
to SOAP 1.2 rules.

=item typelookup

    $client->typelookup;

This method is a shortcut for:

    $client->serializer->typelookup;

Gives the application access to the type-lookup table from the serializer
object. See the section on L<SOAP::Serializer>.

=item uri(service specifier)

Deprecated - the C<uri> subroutine is deprecated in order to provide a more
intuitive naming scheme for subroutines that set namespaces. In the future,
you will be required to use either the C<ns()> or C<default_ns()> subroutines
instead of C<uri()>.

    $client->uri($service_uri);

This method is a shortcut for:

    $client->serializer->uri(service);

The URI associated with this accessor on a client object is the
service-specifier for the request, often encoded for HTTP-based requests as
the SOAPAction header. While the names may seem confusing, this method
doesn't specify the endpoint itself. In most circumstances, the C<uri> refers
to the namespace used for the request.

Often times, the value may look like a valid URL. Despite this, it doesn't
have to point to an existing resource (and often doesn't). This method sets
and retrieves this value from the object. Note that no transport code is
triggered by this because it has no direct effect on the transport of the
object.

=item multirefinplace(boolean)

    $client->multirefinplace(1);

This method is a shortcut for:

    $client->serializer->multirefinplace(boolean);

Controls how the serializer handles values that have multiple references to
them. Recall from previous SOAP chapters that a value may be tagged with an
identifier, then referred to in several places. When this is the case for a
value, the serializer defaults to putting the data element towards the top of
the message, right after the opening tag of the method-specification. It is
serialized as a standalone entity with an ID that is then referenced at the
relevant places later on. If this method is used to set a true value, the
behavior is different. When the multirefinplace attribute is true, the data
is serialized at the first place that references it, rather than as a separate
element higher up in the body. This is more compact but may be harder to read
or trace in a debugging environment.

=item parts( ARRAY )

Used to specify an array of L<MIME::Entity>'s to be attached to the
transmitted SOAP message. Attachments that are returned in a response can be
accessed by C<SOAP::SOM::parts()>.

=item self

    $ref = SOAP::Lite->self;

Returns an object reference to the default global object the C<SOAP::Lite>
package maintains. This is the object that processes many of the arguments
when provided on the use line.

=back

The following method isn't an accessor style of method but neither does it fit
with the group that immediately follows it:

=over

=item call(arguments)

    $client->call($method => @arguments);

As has been illustrated in previous chapters, the C<SOAP::Lite> client objects
can manage remote calls with auto-dispatching using some of Perl's more
elaborate features. call is used when the application wants a greater degree
of control over the details of the call itself. The method may be built up
from a L<SOAP::Data> object, so as to allow full control over the namespace
associated with the tag, as well as other attributes like encoding. This is
also important for calling methods that contain characters not allowable in
Perl function names, such as A.B.C.

=back

The next four methods used in the C<SOAP::Lite> class are geared towards
handling the types of events than can occur during the message lifecycle. Each
of these sets up a callback for the event in question:

=over

=item on_action(callback)

    $client->on_action(sub { qq("$_[0]") });

Triggered when the transport object sets up the SOAPAction header for an
HTTP-based call. The default is to set the header to the string, uri#method,
in which URI is the value set by the uri method described earlier, and method
is the name of the method being called. When called, the routine referenced
(or the closure, if specified as in the example) is given two arguments, uri
and method, in that order.

.NET web services usually expect C</> as separator for C<uri> and C<method>.
To change SOAP::Lite's behaviour to use uri/method as SOAPAction header, use
the following code:

    $client->on_action( sub { join '/', @_ } );
=item on_fault(callback)

    $client->on_fault(sub { popup_dialog($_[1]) });

Triggered when a method call results in a fault response from the server.
When it is called, the argument list is first the client object itself,
followed by the object that encapsulates the fault. In the example, the fault
object is passed (without the client object) to a hypothetical GUI function
that presents an error dialog with the text of fault extracted from the object
(which is covered shortly under the L<SOAP::SOM> methods).

=item on_nonserialized(callback)

    $client->on_nonserialized(sub { die "$_[0]?!?" });

Occasionally, the serializer may be given data it can't turn into SOAP-savvy
XML; for example, if a program bug results in a code reference or something
similar being passed in as a parameter to method call. When that happens, this
callback is activated, with one argument. That argument is the data item that
could not be understood. It will be the only argument. If the routine returns,
the return value is pasted into the message as the serialization. Generally,
an error is in order, and this callback allows for control over signaling that
error.

=item on_debug(callback)

    $client->on_debug(sub { print @_ });

Deprecated. Use the global +debug and +trace facilities described in
L<SOAP::Trace>

Note that this method will not work as expected: Instead of affecting the
debugging behaviour of the object called on, it will globally affect the
debugging behaviour for all objects of that class.

=back

=head1 WRITING A SOAP CLIENT

This chapter guides you to writing a SOAP client by example.

The SOAP service to be accessed is a simple variation of the well-known
hello world program. It accepts two parameters, a name and a given name,
and returns "Hello $given_name $name".

We will use Martin Kutter as the name for the call, so all variants will print
the following message on success:

 Hello Martin Kutter!

=head2 SOAP message styles

There are three common (and one less common) variants of SOAP messages.

These adress the message style (positional parameters vs. specified message
documents) and encoding (as-is vs. typed).

The different message styles are:

=over

=item * rpc/encoded

Typed, positional parameters. Widely used in scripting languages.
The type of the arguments is included in the message.
Arrays and the like may be encoded using SOAP encoding rules (or others).

=item * rpc/literal

As-is, positional parameters. The type of arguments is defined by some
pre-exchanged interface definition.

=item * document/encoded

Specified message with typed elements. Rarely used.

=item * document/literal

Specified message with as-is elements. The message specification and
element types are defined by some pre-exchanged interface definition.

=back

As of 2008, document/literal has become the predominant SOAP message
variant. rpc/literal and rpc/encoded are still in use, mainly with scripting
languages, while document/encoded is hardly used at all.

You will see clients for all common SOAP variants in this section.

=head2 Example implementations

=head3 RPC/ENCODED

The web service accepts the parameters in the order "name", "given name".
There's no interface definition.

A web service client looks like this.

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:80/helloworld.pl');

 my $som = $soap->call(sayHello, 'Kutter', 'Martin'),
 die $som->fault->{ faultstring } if ($som->fault);
 print $som->result, "\n";

=head3 RPC/LITERAL

SOAP web services using the document/literal message encoding are usually
described by some Web Service Definition. Our web service has the following
WSDL description:

 <?xml version="1.0" encoding="UTF-8"?>
 <definitions xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
    xmlns:s="http://www.w3.org/2001/XMLSchema"
    xmlns:s0="urn:HelloWorld"
    targetNamespace="urn:HelloWorld"
    xmlns="http://schemas.xmlsoap.org/wsdl/">
   <types>
     <s:schema targetNamespace="urn:HelloWorld">
       <s:complexType name="sayHello">
         <s:sequence>
            <s:element minOccurs="0" maxOccurs="1" name="name" type="s:string" />
             <s:element minOccurs="0" maxOccurs="1" name="givenName" type="s:string" nillable="1" />
         </s:sequence>
        </s:complexType>

        <s:complexType name="sayHelloResponse">
          <s:sequence>
            <s:element minOccurs="0" maxOccurs="1" name="sayHelloResult" type="s:string" />
          </s:sequence>
      </s:complexType>
    </types>
    <message name="sayHello">
      <part name="parameters" type="s0:sayHello" />
    </message>
    <message name="sayHelloResponse">
      <part name="parameters" type="s0:sayHelloResponse" />
    </message>

    <portType name="Service1Soap">
      <operation name="sayHello">
        <input message="s0:sayHelloSoapIn" />
        <output message="s0:sayHelloSoapOut" />
      </operation>
    </portType>

    <binding name="Service1Soap" type="s0:Service1Soap">
      <soap:binding transport="http://schemas.xmlsoap.org/soap/http"
          style="rpc" />
      <operation name="sayHello">
        <soap:operation soapAction="urn:HelloWorld#sayHello"/>
        <input>
          <soap:body use="literal" />
        </input>
        <output>
          <soap:body use="literal" />
        </output>
      </operation>
    </binding>
    <service name="HelloWorld">
      <port name="HelloWorldSoap" binding="s0:Service1Soap">
        <soap:address location="http://localhost:80//helloworld.pl" />
      </port>
    </service>
  </definitions>

The XML message (inside the SOAP Envelope) look like this:

 <sayHello xmlns="urn:HelloWorld">
   <name>Kutter</name>
   <givenName>Martin</givenName>
 </sayHello>

 <sayHelloResponse>
   <sayHelloResult>Hello Martin Kutter!</sayHelloResult>
 </sayHelloResponse>

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:80/helloworld.pl');

 $soap->on_action( sub { "urn:HelloWorld#sayHello" });
 $soap->autotype(0);
 $soap->default_ns('urn:HelloWorld');

 my $som = $soap->call('sayHello'
    SOAP::Data->name('name')->value( 'Kutter' ),
    SOAP::Data->name('givenName')->value('Martin'),
);

 die $som->fault->{ faultstring } if ($som->fault);
 print $som->result, "\n";

=head3 DOCUMENT/LITERAL

SOAP web services using the document/literal message encoding are usually
described by some Web Service Definition. Our web service has the following
WSDL description:

 <?xml version="1.0" encoding="UTF-8"?>
 <definitions xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
    xmlns:s="http://www.w3.org/2001/XMLSchema"
    xmlns:s0="urn:HelloWorld"
    targetNamespace="urn:HelloWorld"
    xmlns="http://schemas.xmlsoap.org/wsdl/">
   <types>
     <s:schema targetNamespace="urn:HelloWorld">
       <s:element name="sayHello">
         <s:complexType>
           <s:sequence>
              <s:element minOccurs="0" maxOccurs="1" name="name" type="s:string" />
               <s:element minOccurs="0" maxOccurs="1" name="givenName" type="s:string" nillable="1" />
           </s:sequence>
          </s:complexType>
        </s:element>

        <s:element name="sayHelloResponse">
          <s:complexType>
            <s:sequence>
              <s:element minOccurs="0" maxOccurs="1" name="sayHelloResult" type="s:string" />
            </s:sequence>
        </s:complexType>
      </s:element>
    </types>
    <message name="sayHelloSoapIn">
      <part name="parameters" element="s0:sayHello" />
    </message>
    <message name="sayHelloSoapOut">
      <part name="parameters" element="s0:sayHelloResponse" />
    </message>

    <portType name="Service1Soap">
      <operation name="sayHello">
        <input message="s0:sayHelloSoapIn" />
        <output message="s0:sayHelloSoapOut" />
      </operation>
    </portType>

    <binding name="Service1Soap" type="s0:Service1Soap">
      <soap:binding transport="http://schemas.xmlsoap.org/soap/http"
          style="document" />
      <operation name="sayHello">
        <soap:operation soapAction="urn:HelloWorld#sayHello"/>
        <input>
          <soap:body use="literal" />
        </input>
        <output>
          <soap:body use="literal" />
        </output>
      </operation>
    </binding>
    <service name="HelloWorld">
      <port name="HelloWorldSoap" binding="s0:Service1Soap">
        <soap:address location="http://localhost:80//helloworld.pl" />
      </port>
    </service>
  </definitions>

The XML message (inside the SOAP Envelope) look like this:

 <sayHello xmlns="urn:HelloWorld">
   <name>Kutter</name>
   <givenName>Martin</givenName>
 </sayHello>

 <sayHelloResponse>
   <sayHelloResult>Hello Martin Kutter!</sayHelloResult>
 </sayHelloResponse>

You can call this web service with the following client code:

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:80/helloworld.pl');

 $soap->on_action( sub { "urn:HelloWorld#sayHello" });
 $soap->autotype(0);
 $soap->default_ns('urn:HelloWorld');

 my $som = $soap->call("sayHello",
    SOAP::Data->name('name')->value( 'Kutter' ),
    SOAP::Data->name('givenName')->value('Martin'),
);

 die $som->fault->{ faultstring } if ($som->fault);
 print $som->result, "\n";

=head2 Differences between the implementations

You may have noticed that there's no between the rpc/literal
and the document/literal example's implementation. In fact, from SOAP::Lite's
point of view, the only differences between rpc/literal and document/literal
that parameters are always named.

In our example, the rpc/literal variant already used named parameters (by
using a single complexType only as positional parameter), so there's no
difference at all.

The differences would have been bigger if the rpc/literal example had used
more than one positional parameter, but this is quite unlikely to happen in
the future: Current interoperability standards (like the WS-I basic profile)
mandate the use of a single complexType as only parameter in rpc/literal
calls.

=head1 WRITING A SOAP SERVER

See L<SOAP::Server>, or L<SOAP::Transport>.

=head1 FEATURES

=head2 ATTACHMENTS

C<SOAP::Lite> features support for the SOAP with Attachments specification.
Currently, SOAP::Lite only supports MIME based attachments. DIME based
attachments are yet to be fully functional.

=head3 EXAMPLES

=head4 Client sending an attachment

C<SOAP::Lite> clients can specify attachments to be sent along with a request
by using the C<SOAP::Lite::parts()> method, which takes as an argument an
ARRAY of C<MIME::Entity>'s.

  use SOAP::Lite;
  use MIME::Entity;
  my $ent = build MIME::Entity
    Type        => "image/gif",
    Encoding    => "base64",
    Path        => "somefile.gif",
    Filename    => "saveme.gif",
    Disposition => "attachment";
  my $som = SOAP::Lite
    ->uri($SOME_NAMESPACE)
    ->parts([ $ent ])
    ->proxy($SOME_HOST)
    ->some_method(SOAP::Data->name("foo" => "bar"));

=head4 Client retrieving an attachment

A client accessing attachments that were returned in a response by using the
C<SOAP::SOM::parts()> accessor.

  use SOAP::Lite;
  use MIME::Entity;
  my $soap = SOAP::Lite
    ->uri($NS)
    ->proxy($HOST);
  my $som = $soap->foo();
  foreach my $part (${$som->parts}) {
    print $part->stringify;
  }

=head4 Server receiving an attachment

Servers, like clients, use the S<SOAP::SOM> module to access attachments
trasmitted to it.

  package Attachment;
  use SOAP::Lite;
  use MIME::Entity;
  use strict;
  use vars qw(@ISA);
  @ISA = qw(SOAP::Server::Parameters);
  sub someMethod {
    my $self = shift;
    my $envelope = pop;
    foreach my $part (@{$envelope->parts}) {
      print "AttachmentService: attachment found! (".ref($part).")\n";
    }
    # do something
  }

=head4 Server responding with an attachment

Servers wishing to return an attachment to the calling client need only return
C<MIME::Entity> objects along with SOAP::Data elements, or any other data
intended for the response.

  package Attachment;
  use SOAP::Lite;
  use MIME::Entity;
  use strict;
  use vars qw(@ISA);
  @ISA = qw(SOAP::Server::Parameters);
  sub someMethod {
    my $self = shift;
    my $envelope = pop;
    my $ent = build MIME::Entity
	'Id'          => "<1234>",
	'Type'        => "text/xml",
	'Path'        => "some.xml",
	'Filename'    => "some.xml",
	'Disposition' => "attachment";
    return SOAP::Data->name("foo" => "blah blah blah"),$ent;
  }

=head2 DEFAULT SETTINGS

Though this feature looks similar to
L<autodispatch|/"IN/OUT, OUT PARAMETERS AND AUTOBINDING"> they have (almost)
nothing in common. This capability allows you specify default settings so that
all objects created after that will be initialized with the proper default
settings.

If you wish to provide common C<proxy()> or C<uri()> settings for all
C<SOAP::Lite> objects in your application you may do:

  use SOAP::Lite
    proxy => 'http://localhost/cgi-bin/soap.cgi',
    uri => 'http://my.own.com/My/Examples';

  my $soap1 = new SOAP::Lite; # will get the same proxy()/uri() as above
  print $soap1->getStateName(1)->result;

  my $soap2 = SOAP::Lite->new; # same thing as above
  print $soap2->getStateName(2)->result;

  # or you may override any settings you want
  my $soap3 = SOAP::Lite->proxy('http://localhost/');
  print $soap3->getStateName(1)->result;

B<Any> C<SOAP::Lite> properties can be propagated this way. Changes in object
copies will not affect global settings and you may still change global
settings with C<< SOAP::Lite->self >> call which returns reference to global
object. Provided parameter will update this object and you can even set it to
C<undef>:

  SOAP::Lite->self(undef);

The C<use SOAP::Lite> syntax also lets you specify default event handlers for
your code. If you have different SOAP objects and want to share the same
C<on_action()> (or C<on_fault()> for that matter) handler. You can specify
C<on_action()> during initialization for every object, but you may also do:

  use SOAP::Lite
    on_action => sub {sprintf '%s#%s', @_};

and this handler will be the default handler for all your SOAP objects. You
can override it if you specify a handler for a particular object. See F<t/*.t>
for example of on_fault() handler.

Be warned, that since C<use ...> is executed at compile time B<all> C<use>
statements will be executed B<before> script execution that can make
unexpected results. Consider code:

  use SOAP::Lite proxy => 'http://localhost/';
  print SOAP::Lite->getStateName(1)->result;

  use SOAP::Lite proxy => 'http://localhost/cgi-bin/soap.cgi';
  print SOAP::Lite->getStateName(1)->result;

B<Both> SOAP calls will go to C<'http://localhost/cgi-bin/soap.cgi'>. If you
want to execute C<use> at run-time, put it in C<eval>:

  eval "use SOAP::Lite proxy => 'http://localhost/cgi-bin/soap.cgi'; 1" or die;

Or alternatively,

  SOAP::Lite->self->proxy('http://localhost/cgi-bin/soap.cgi');

=head2 SETTING MAXIMUM MESSAGE SIZE

One feature of C<SOAP::Lite> is the ability to control the maximum size of a
message a SOAP::Lite server will be allowed to process. To control this
feature simply define C<$SOAP::Constants::MAX_CONTENT_SIZE> in your code like
so:

  use SOAP::Transport::HTTP;
  use MIME::Entity;
  $SOAP::Constants::MAX_CONTENT_SIZE = 10000;
  SOAP::Transport::HTTP::CGI
    ->dispatch_to('TemperatureService')
    ->handle;

=head2 IN/OUT, OUT PARAMETERS AND AUTOBINDING

C<SOAP::Lite> gives you access to all parameters (both in/out and out) and
also does some additional work for you. Lets consider following example:

  <mehodResponse>
    <res1>name1</res1>
    <res2>name2</res2>
    <res3>name3</res3>
  </mehodResponse>

In that case:

  $result = $r->result; # gives you 'name1'
  $paramout1 = $r->paramsout;      # gives you 'name2', because of scalar context
  $paramout1 = ($r->paramsout)[0]; # gives you 'name2' also
  $paramout2 = ($r->paramsout)[1]; # gives you 'name3'

or

  @paramsout = $r->paramsout; # gives you ARRAY of out parameters
  $paramout1 = $paramsout[0]; # gives you 'res2', same as ($r->paramsout)[0]
  $paramout2 = $paramsout[1]; # gives you 'res3', same as ($r->paramsout)[1]

Generally, if server returns C<return (1,2,3)> you will get C<1> as the result
and C<2> and C<3> as out parameters.

If the server returns C<return [1,2,3]> you will get an ARRAY reference from
C<result()> and C<undef> from C<paramsout()>.

Results can be arbitrary complex: they can be an array references, they can be
objects, they can be anything and still be returned by C<result()> . If only
one parameter is returned, C<paramsout()> will return C<undef>.

Furthermore, if you have in your output parameters a parameter with the same
signature (name+type) as in the input parameters this parameter will be mapped
into your input automatically. For example:

B<Server Code>:

  sub mymethod {
    shift; # object/class reference
    my $param1 = shift;
    my $param2 = SOAP::Data->name('myparam' => shift() * 2);
    return $param1, $param2;
  }

B<Client Code>:

  $a = 10;
  $b = SOAP::Data->name('myparam' => 12);
  $result = $soap->mymethod($a, $b);

After that, C<< $result == 10 and $b->value == 24 >>! Magic? Sort of.

Autobinding gives it to you. That will work with objects also with one
difference: you do not need to worry about the name and the type of object
parameter. Consider the C<PingPong> example (F<examples/My/PingPong.pm>
and F<examples/pingpong.pl>):

B<Server Code>:

  package My::PingPong;

  sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    bless {_num=>shift} => $class;
  }

  sub next {
    my $self = shift;
    $self->{_num}++;
  }

B<Client Code>:

  use SOAP::Lite +autodispatch =>
    uri => 'urn:',
    proxy => 'http://localhost/';

  my $p = My::PingPong->new(10); # $p->{_num} is 10 now, real object returned
  print $p->next, "\n";          # $p->{_num} is 11 now!, object autobinded

=head2 STATIC AND DYNAMIC SERVICE DEPLOYMENT

Let us scrutinize the deployment process. When designing your SOAP server you
can consider two kind of deployment: B<static> and B<dynamic>. For both,
static and dynamic,  you should specify C<MODULE>, C<MODULE::method>,
C<method> or C<PATH/> when creating C<use>ing the SOAP::Lite module. The
difference between static and dynamic deployment is that in case of 'dynamic',
any module which is not present will be loaded on demand. See the
L</"SECURITY"> section for detailed description.

When statically deploying a SOAP Server, you need to know all modules handling
SOAP requests before.

Dynamic deployment allows extending your SOAP Server's interface by just
installing another module into the dispatch_to path (see below).

=head3 STATIC DEPLOYMENT EXAMPLE

  use SOAP::Transport::HTTP;
  use My::Examples;           # module is preloaded

  SOAP::Transport::HTTP::CGI
     # deployed module should be present here or client will get
     # 'access denied'
    -> dispatch_to('My::Examples')
    -> handle;

For static deployment you should specify the MODULE name directly.

You should also use static binding when you have several different classes in
one file and want to make them available for SOAP calls.

=head3 DYNAMIC DEPLOYMENT EXAMPLE

  use SOAP::Transport::HTTP;
  # name is unknown, module will be loaded on demand

  SOAP::Transport::HTTP::CGI
    # deployed module should be present here or client will get 'access denied'
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'My::Examples')
    -> handle;

For dynamic deployment you can specify the name either directly (in that case
it will be C<require>d without any restriction) or indirectly, with a PATH. In
that case, the ONLY path that will be available will be the PATH given to the
dispatch_to() method). For information how to handle this situation see
L</"SECURITY"> section.

=head3 SUMMARY

  dispatch_to(
    # dynamic dispatch that allows access to ALL modules in specified directory
    PATH/TO/MODULES
    # 1. specifies directory
    # -- AND --
    # 2. gives access to ALL modules in this directory without limits

    # static dispatch that allows access to ALL methods in particular MODULE
    MODULE
    #  1. gives access to particular module (all available methods)
    #  PREREQUISITES:
    #    module should be loaded manually (for example with 'use ...')
    #    -- OR --
    #    you can still specify it in PATH/TO/MODULES

    # static dispatch that allows access to particular method ONLY
    MODULE::method
    # same as MODULE, but gives access to ONLY particular method,
    # so there is not much sense to use both MODULE and MODULE::method
    # for the same MODULE
  );

In addition to this C<SOAP::Lite> also supports an experimental syntax that
allows you to bind a specific URL or SOAPAction to a CLASS/MODULE or object.

For example:

  dispatch_with({
    URI => MODULE,        # 'http://www.soaplite.com/' => 'My::Class',
    SOAPAction => MODULE, # 'http://www.soaplite.com/method' => 'Another::Class',
    URI => object,        # 'http://www.soaplite.com/obj' => My::Class->new,
  })

C<URI> is checked before C<SOAPAction>. You may use both the C<dispatch_to()>
and C<dispatch_with()> methods in the same server, but note that
C<dispatch_with()> has a higher order of precedence. C<dispatch_to()> will be
checked only after C<URI> and C<SOAPAction> has been checked.

See also:
L<EXAMPLE APACHE::REGISTRY USAGE|SOAP::Transport/"EXAMPLE APACHE::REGISTRY USAGE">,
L</"SECURITY">

=head2 COMPRESSION

C<SOAP::Lite> provides you option to enable transparent compression over the
wire. Compression can be enabled by specifying a threshold value (in the form
of kilobytes) for compression on both the client and server sides:

I<Note: Compression currently only works for HTTP based servers and clients.>

B<Client Code>

  print SOAP::Lite
    ->uri('http://localhost/My/Parameters')
    ->proxy('http://localhost/', options => {compress_threshold => 10000})
    ->echo(1 x 10000)
    ->result;

B<Server Code>

  my $server = SOAP::Transport::HTTP::CGI
    ->dispatch_to('My::Parameters')
    ->options({compress_threshold => 10000})
    ->handle;

For more information see L<COMPRESSION|SOAP::Transport/"COMPRESSION"> in
L<HTTP::Transport>.

=head1 SECURITY

For security reasons, the exisiting path for Perl modules (C<@INC>) will be
disabled once you have chosen dynamic deployment and specified your own
C<PATH/>. If you wish to access other modules in your included package you
have several options:

=over 4

=item 1

Switch to static linking:

   use MODULE;
   $server->dispatch_to('MODULE');

Which can also be useful when you want to import something specific from the
deployed modules:

   use MODULE qw(import_list);

=item 2

Change C<use> to C<require>. The path is only unavailable during the
initialization phase. It is available once more during execution. Therefore,
if you utilize C<require> somewhere in your package, it will work.

=item 3

Wrap C<use> in an C<eval> block:

   eval 'use MODULE qw(import_list)'; die if $@;

=item 4

Set your include path in your package and then specify C<use>. Don't forget to
put C<@INC> in a C<BEGIN{}> block or it won't work. For example,

   BEGIN { @INC = qw(my_directory); use MODULE }

=back

=head1 INTEROPERABILITY

=head2 Microsoft .NET client with SOAP::Lite Server

In order to use a .NET client with a SOAP::Lite server, be sure you use fully
qualified names for your return values. For example:

  return SOAP::Data->name('myname')
                   ->type('string')
                   ->uri($MY_NAMESPACE)
                   ->value($output);

In addition see comment about default incoding in .NET Web Services below.

=head2 SOAP::Lite client with a .NET server

If experiencing problems when using a SOAP::Lite client to call a .NET Web
service, it is recommended you check, or adhere to all of the following
recommendations:

=over 4

=item Declare a proper soapAction in your call

For example, use
C<on_action( sub { 'http://www.myuri.com/WebService.aspx#someMethod'; } )>.

=item Disable charset definition in Content-type header

Some users have said that Microsoft .NET prefers the value of
the Content-type header to be a mimetype exclusively, but SOAP::Lite specifies
a character set in addition to the mimetype. This results in an error similar
to:

  Server found request content type to be 'text/xml; charset=utf-8',
  but expected 'text/xml'

To turn off this behavior specify use the following code:

  use SOAP::Lite;
  $SOAP::Constants::DO_NOT_USE_CHARSET = 1;
  # The rest of your code

=item Use fully qualified name for method parameters

For example, the following code is preferred:

  SOAP::Data->name(Query  => 'biztalk')
            ->uri('http://tempuri.org/')

As opposed to:

  SOAP::Data->name('Query'  => 'biztalk')

=item Place method in default namespace

For example, the following code is preferred:

  my $method = SOAP::Data->name('add')
                         ->attr({xmlns => 'http://tempuri.org/'});
  my @rc = $soap->call($method => @parms)->result;

As opposed to:

  my @rc = $soap->call(add => @parms)->result;
  # -- OR --
  my @rc = $soap->add(@parms)->result;

=item Disable use of explicit namespace prefixes

Some user's have reported that .NET will simply not parse messages that use
namespace prefixes on anything but SOAP elements themselves. For example, the
following XML would not be parsed:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <namesp1:mymethod xmlns:namesp1="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

SOAP::Lite allows users to disable the use of explicit namespaces through the
C<use_prefix()> method. For example, the following code:

  $som = SOAP::Lite->uri('urn:MyURI')
                   ->proxy($HOST)
                   ->use_prefix(0)
                   ->myMethod();

Will result in the following XML, which is more pallatable by .NET:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <mymethod xmlns="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

=item Modify your .NET server, if possible

Stefan Pharies <stefanph@microsoft.com>:

SOAP::Lite uses the SOAP encoding (section 5 of the soap 1.1 spec), and
the default for .NET Web Services is to use a literal encoding. So
elements in the request are unqualified, but your service expects them to
be qualified. .Net Web Services has a way for you to change the expected
message format, which should allow you to get your interop working.
At the top of your class in the asmx, add this attribute (for Beta 1):

  [SoapService(Style=SoapServiceStyle.RPC)]

Another source said it might be this attribute (for Beta 2):

  [SoapRpcService]

Full Web Service text may look like:

  <%@ WebService Language="C#" Class="Test" %>
  using System;
  using System.Web.Services;
  using System.Xml.Serialization;

  [SoapService(Style=SoapServiceStyle.RPC)]
  public class Test : WebService {
    [WebMethod]
    public int add(int a, int b) {
      return a + b;
    }
  }

Another example from Kirill Gavrylyuk <kirillg@microsoft.com>:

"You can insert [SoapRpcService()] attribute either on your class or on
operation level".

  <%@ WebService Language=CS class="DataType.StringTest"%>

  namespace DataType {

    using System;
    using System.Web.Services;
    using System.Web.Services.Protocols;
    using System.Web.Services.Description;

   [SoapRpcService()]
   public class StringTest: WebService {
     [WebMethod]
     [SoapRpcMethod()]
     public string RetString(string x) {
       return(x);
     }
   }
 }

Example from Yann Christensen <yannc@microsoft.com>:

  using System;
  using System.Web.Services;
  using System.Web.Services.Protocols;

  namespace Currency {
    [WebService(Namespace="http://www.yourdomain.com/example")]
    [SoapRpcService]
    public class Exchange {
      [WebMethod]
      public double getRate(String country, String country2) {
        return 122.69;
      }
    }
  }

=back

Special thanks goes to the following people for providing the above
description and details on .NET interoperability issues:

Petr Janata <petr.janata@i.cz>,

Stefan Pharies <stefanph@microsoft.com>,

Brian Jepson <bjepson@jepstone.net>, and others

=head1 TROUBLESHOOTING

=over 4

=item SOAP::Lite serializes "18373" as an integer, but I want it to be a string!

SOAP::Lite guesses datatypes from the content provided, using a set of
common-sense rules. These rules are not 100% reliable, though they fit for
most data.

You may force the type by passing a SOAP::Data object with a type specified:

 my $proxy = SOAP::Lite->proxy('http://www.example.org/soapservice');
 my $som = $proxy->myMethod(
     SOAP::Data->name('foo')->value(12345)->type('string')
 );

You may also change the precedence of the type-guessing rules. Note that this
means fiddling with SOAP::Lite's internals - this may not work as
expected in future versions.

The example above forces everything to be encoded as string (this is because
the string test is normally last and allways returns true):

  my @list = qw(-1 45 foo bar 3838);
  my $proxy = SOAP::Lite->uri($uri)->proxy($proxyUrl);
  $proxy->serializer->typelookup->{string}->[0] = 0;
  $proxy->myMethod(\@list);

See L<SOAP::Serializer|SOAP::Serializer/AUTOTYPING> for more details.

=item C<+autodispatch> doesn't work in Perl 5.8

There is a bug in Perl 5.8's C<UNIVERSAL::AUTOLOAD> functionality that
prevents the C<+autodispatch> functionality from working properly. The
workaround is to use C<dispatch_from> instead. Where you might normally do
something like this:

   use Some::Module;
   use SOAP::Lite +autodispatch =>
       uri => 'urn:Foo'
       proxy => 'http://...';

You would do something like this:

   use SOAP::Lite dispatch_from(Some::Module) =>
       uri => 'urn:Foo'
       proxy => 'http://...';

=item Problems using SOAP::Lite's COM Interface

=over

=item Can't call method "server" on undefined value

You probably did not register F<Lite.dll> using C<regsvr32 Lite.dll>

=item Failed to load PerlCtrl Runtime

It is likely that you have install Perl in two different locations and the
location of ActiveState's Perl is not the first instance of Perl specified
in your PATH. To rectify, rename the directory in which the non-ActiveState
Perl is installed, or be sure the path to ActiveState's Perl is specified
prior to any other instance of Perl in your PATH.

=back

=item Dynamic libraries are not found

If you are using the Apache web server, and you are seeing something like the
following in your webserver log file:

  Can't load '/usr/local/lib/perl5/site_perl/.../XML/Parser/Expat/Expat.so'
    for module XML::Parser::Expat: dynamic linker: /usr/local/bin/perl:
    libexpat.so.0 is NEEDED, but object does not exist at
    /usr/local/lib/perl5/.../DynaLoader.pm line 200.

Then try placing the following into your F<httpd.conf> file and see if it
fixes your problem.

 <IfModule mod_env.c>
     PassEnv LD_LIBRARY_PATH
 </IfModule>

=item SOAP client reports "500 unexpected EOF before status line seen

See L</"Apache is crashing with segfaults">

=item Apache is crashing with segfaults

Using C<SOAP::Lite> (or L<XML::Parser::Expat>) in combination with mod_perl
causes random segmentation faults in httpd processes. To fix, try configuring
Apache with the following:

 RULE_EXPAT=no

If you are using Apache 1.3.20 and later, try configuring Apache with the
following option:

 ./configure --disable-rule=EXPAT

See http://archive.covalent.net/modperl/2000/04/0185.xml for more details and
lot of thanks to Robert Barta <rho@bigpond.net.au> for explaining this weird
behavior.

If this doesn't address the problem, you may wish to try C<-Uusemymalloc>,
or a similar option in order to instruct Perl to use the system's own C<malloc>.

Thanks to Tim Bunce <Tim.Bunce@pobox.com>.

=item CGI scripts do not work under Microsoft Internet Information Server (IIS)

CGI scripts may not work under IIS unless scripts use the C<.pl> extension,
opposed to C<.cgi>.

=item Java SAX parser unable to parse message composed by SOAP::Lite

In some cases SOAP messages created by C<SOAP::Lite> may not be parsed
properly by a SAX2/Java XML parser. This is due to a known bug in
C<org.xml.sax.helpers.ParserAdapter>. This bug manifests itself when an
attribute in an XML element occurs prior to the XML namespace declaration on
which it depends. However, according to the XML specification, the order of
these attributes is not significant.

http://www.megginson.com/SAX/index.html

Thanks to Steve Alpert (Steve_Alpert@idx.com) for pointing on it.

=back

=head1 PERFORMANCE

=over 4

=item Processing of XML encoded fragments

C<SOAP::Lite> is based on L<XML::Parser> which is basically wrapper around
James Clark's expat parser. Expat's behavior for parsing XML encoded string
can affect processing messages that have lot of encoded entities, like XML
fragments, encoded as strings. Providing low-level details, parser will call
char() callback for every portion of processed stream, but individually for
every processed entity or newline. It can lead to lot of calls and additional
memory manager expenses even for small messages. By contrast, XML messages
which are encoded as base64Binary, don't have this problem and difference in
processing time can be significant. For XML encoded string that has about 20
lines and 30 tags, number of call could be about 100 instead of one for
the same string encoded as base64Binary.

Since it is parser's feature there is NO fix for this behavior (let me know
if you find one), especially because you need to parse message you already
got (and you cannot control content of this message), however, if your are
in charge for both ends of processing you can switch encoding to base64 on
sender's side. It will definitely work with SOAP::Lite and it B<may> work with
other toolkits/implementations also, but obviously I cannot guarantee that.

If you want to encode specific string as base64, just do
C<< SOAP::Data->type(base64 => $string) >> either on client or on server
side. If you want change behavior for specific instance of SOAP::Lite, you
may subclass C<SOAP::Serializer>, override C<as_string()> method that is
responsible for string encoding (take a look into C<as_base64Binary()>) and
specify B<new> serializer class for your SOAP::Lite object with:

  my $soap = new SOAP::Lite
    serializer => My::Serializer->new,
    ..... other parameters

or on server side:

  my $server = new SOAP::Transport::HTTP::Daemon # or any other server
    serializer => My::Serializer->new,
    ..... other parameters

If you want to change this behavior for B<all> instances of SOAP::Lite, just
substitute C<as_string()> method with C<as_base64Binary()> somewhere in your
code B<after> C<use SOAP::Lite> and B<before> actual processing/sending:

  *SOAP::Serializer::as_string = \&SOAP::XMLSchema2001::Serializer::as_base64Binary;

Be warned that last two methods will affect B<all> strings and convert them
into base64 encoded. It doesn't make any difference for SOAP::Lite, but it
B<may> make a difference for other toolkits.

=back

=head1 BUGS AND LIMITATIONS

=over 4

=item *

No support for multidimensional, partially transmitted and sparse arrays
(however arrays of arrays are supported, as well as any other data structures,
and you can add your own implementation with SOAP::Data).

=item *

Limited support for WSDL schema.

=item *

XML::Parser::Lite relies on Unicode support in Perl and doesn't do entity decoding.

=item *

Limited support for mustUnderstand and Actor attributes.

=back

=head1 PLATFORM SPECIFICS

=over 4

=item MacOS

Information about XML::Parser for MacPerl could be found here:

http://bumppo.net/lists/macperl-modules/1999/07/msg00047.html

Compiled XML::Parser for MacOS could be found here:

http://www.perl.com/CPAN-local/authors/id/A/AS/ASANDSTRM/XML-Parser-2.27-bin-1-MacOS.tgz

=back

=head1 AVAILABILITY

You can download the latest version SOAP::Lite for Unix or SOAP::Lite for
Win32 from the following sources:

 * CPAN:                http://search.cpan.org/search?dist=SOAP-Lite
 * Sourceforge:         http://sourceforge.net/projects/soaplite/

PPM packages are also available from sourceforge.

You are welcome to send e-mail to the maintainers of SOAP::Lite with your
with your comments, suggestions, bug reports and complaints.

=head1 ACKNOWLEDGEMENTS

Special thanks to Randy J. Ray, author of
I<Programming Web Services with Perl>, who has contributed greatly to the
documentation effort of SOAP::Lite.

Special thanks to O'Reilly publishing which has graciously allowed SOAP::Lite
to republish and redistribute the SOAP::Lite reference manual found in
Appendix B of I<Programming Web Services with Perl>.

And special gratitude to all the developers who have contributed patches,
ideas, time, energy, and help in a million different forms to the development
of this software.

=head1 HACKING

SOAP::Lite's developement takes place on sourceforge.net.

There's a subversion repository set up at

 https://soaplite.svn.sourceforge.net/svnroot/soaplite/

=head1 REPORTING BUGS

Please report all suspected SOAP::Lite bugs using Sourceforge. This ensures
proper tracking of the issue and allows you the reporter to know when something
gets fixed.

http://sourceforge.net/tracker/?group_id=66000&atid=513017

=head1 COPYRIGHT

Copyright (C) 2000-2007 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This text and all associated documentation for this library is made available
under the Creative Commons Attribution-NoDerivs 2.0 license.
http://creativecommons.org/licenses/by-nd/2.0/

=head1 AUTHORS

Paul Kulchenko (paulclinger@yahoo.com)

Randy J. Ray (rjray@blackperl.com)

Byrne Reese (byrne@majordojo.com)

Martin Kutter (martin.kutter@fen-net.de)

=cut
