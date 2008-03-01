package SOAP::Transport;

use strict;

use vars qw($AUTOLOAD @ISA);

use SOAP::Trace;
use SOAP::Cloneable;
use SOAP::Client;

@ISA = qw(SOAP::Cloneable);

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = ref($self) || $self;

    SOAP::Trace::objects('()');
    return bless {} => $class;
}

sub proxy {
    my $self = shift;
    $self = $self->new() if not ref $self;

    my $class = ref $self;

    return $self->{_proxy} unless @_;

    $_[0] =~ /^(\w+):/ or die "proxy: transport protocol not specified\n";
    my $protocol = uc "$1"; # untainted now

    # HTTPS is handled by HTTP class
    $protocol =~s/^HTTPS$/HTTP/;

    (my $protocol_class = "${class}::$protocol") =~ s/-/_/g;

    no strict 'refs';
    unless (defined %{"$protocol_class\::Client::"}
        && UNIVERSAL::can("$protocol_class\::Client" => 'new')
    ) {
        eval "require $protocol_class";
        die "Unsupported protocol '$protocol'\n"
            if $@ =~ m!^Can\'t locate SOAP/Transport/!;
        die if $@;
    }

    $protocol_class .= "::Client";
    return $self->{_proxy} = $protocol_class->new(endpoint => shift, @_);
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    no strict 'refs';
    *$AUTOLOAD = sub { shift->proxy->$method(@_) };
    goto &$AUTOLOAD;
}

1;

__END__