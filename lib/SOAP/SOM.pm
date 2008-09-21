package SOAP::SOM;

use strict;

use Carp ();
use SOAP::Lite::Utils;
use SOAP::Fault;
use SOAP::Server::Object;

sub BEGIN {
    no strict 'refs';
    my %path = (
        root        => '/',
        envelope    => '/Envelope',
        body        => '/Envelope/Body',
        header      => '/Envelope/Header',
        headers     => '/Envelope/Header/[>0]',
        fault       => '/Envelope/Body/Fault',
        faultcode   => '/Envelope/Body/Fault/faultcode',
        faultstring => '/Envelope/Body/Fault/faultstring',
        faultactor  => '/Envelope/Body/Fault/faultactor',
        faultdetail => '/Envelope/Body/Fault/detail',
    );
    for my $method ( keys %path ) {
        *$method = sub {
            my $self = shift;
            ref $self or return $path{$method};
            Carp::croak
              "Method '$method' is readonly and doesn't accept any parameters"
              if @_;
            return $self->valueof( $path{$method} );
        };
    }
    my %results = (
        method    => '/Envelope/Body/[1]',
        result    => '/Envelope/Body/[1]/[1]',
        freeform  => '/Envelope/Body/[>0]',
        paramsin  => '/Envelope/Body/[1]/[>0]',
        paramsall => '/Envelope/Body/[1]/[>0]',
        paramsout => '/Envelope/Body/[1]/[>1]'
    );
    for my $method ( keys %results ) {
        *$method = sub {
            my $self = shift;
            ref $self or return $results{$method};
            Carp::croak
              "Method '$method' is readonly and doesn't accept any parameters"
              if @_;
            defined $self->fault
              ? return
              : return $self->valueof( $results{$method} );
        };
    }

    for my $method (qw(o_child o_value o_lname o_lattr o_qname))
    {    # import from SOAP::Utils
        *$method = \&{'SOAP::Utils::' . $method};
    }

    __PACKAGE__->__mk_accessors('context');

}

# use object in boolean context return true/false on last match
# Ex.: $som->match('//Fault') ? 'SOAP call failed' : 'success';
use overload fallback => 1, 'bool' => sub { @{shift->{_current}} > 0 };

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self    = shift;
    my $class   = ref($self) || $self;
    my $content = shift;
    SOAP::Trace::objects('()');
    return bless {_content => $content, _current => [$content]} => $class;
}

sub parts {
    my $self = shift;
    if (@_) {
        $self->context->packager->parts(@_);
        return $self;
    }
    else {
        return $self->context->packager->parts;
    }
}

sub is_multipart {
    my $self = shift;
    return defined( $self->parts );
}

sub current {
    my $self = shift;
    $self->{_current} = [@_], return $self if @_;
    return wantarray ? @{$self->{_current}} : $self->{_current}->[0];
}

sub valueof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return
        wantarray ? map { o_value($_) } @{$self->{_current}}
      : @{$self->{_current}} ? o_value( $self->{_current}->[0] )
      :                        undef;
}

sub headerof {    # SOAP::Header is the same as SOAP::Data, so just rebless it
    wantarray
      ? map { bless $_ => 'SOAP::Header' } shift->dataof(@_)
      : do {      # header returned by ->dataof can be undef in scalar context
        my $header = shift->dataof(@_);
        ref $header ? bless( $header => 'SOAP::Header' ) : undef;
      };
}

sub dataof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return
        wantarray ? map { $self->_as_data($_) } @{$self->{_current}}
      : @{$self->{_current}} ? $self->_as_data( $self->{_current}->[0] )
      :                        undef;
}

sub namespaceuriof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return
      wantarray ? map { ( SOAP::Utils::splitlongname( o_lname($_) ) )[0] }
      @{$self->{_current}}
      : @{$self->{_current}}
      ? ( SOAP::Utils::splitlongname( o_lname( $self->{_current}->[0] ) ) )[0]
      : undef;
}

#sub _as_data {
#    my $self = shift;
#    my $pointer = shift;
#
#    SOAP::Data
#        -> new(prefix => '',
#               name => o_qname($pointer),
#               name => o_lname($pointer), attr => o_lattr($pointer))
#        -> set_value(o_value($pointer));
#}

sub _as_data {
    my $self = shift;
    my $node = shift;

    my $data = SOAP::Data->new( prefix => '',
        # name => o_qname has side effect: sets namespace !
        name => SOAP::Lite::Utils::o_qname($node),
        name => SOAP::Lite::Utils::o_lname($node),
        attr =>  SOAP::Lite::Utils::o_lattr($node) );

    if ( defined SOAP::Lite::Utils::o_child($node) ) {
        my @children;
        foreach my $child ( @{ SOAP::Lite::Utils::o_child($node) } ) {
            push( @children, $self->_as_data($child) );
        }
        $data->set_value( \SOAP::Data->value(@children) );
    }
    else {
        $data->set_value( SOAP::Lite::Utils::o_value($node) );
    }

    return $data;
}

sub match {
    my $self = shift;
    my $path = shift;
    $self->{_current} = [
          $path =~ s!^/!! || !@{$self->{_current}}
        ? $self->_traverse( $self->{_content}, 1 => split '/' => $path )
        : map { $self->_traverse_tree( o_child($_), split '/' => $path ) }
          @{$self->{_current}}];
    return $self;
}

sub _traverse {
    my $self = shift;
    my ( $pointer, $itself, $path, @path ) = @_;

    die "Incorrect parameter" unless $itself =~ /^\d*$/;

    if ( $path && substr( $path, 0, 1 ) eq '{' ) {
        $path = join '/', $path, shift @path while @path && $path !~ /}/;
    }

    my ( $op, $num ) = $path =~ /^\[(<=|<|>=|>|=|!=?)?(\d+)\]$/
      if defined $path;

    return $pointer unless defined $path;

    $op = '==' unless $op;
    $op .= '=' if $op eq '=' || $op eq '!';
    my $numok = defined $num && eval "$itself $op $num";
    my $nameok = ( o_lname($pointer) || '' ) =~ /(?:^|\})$path$/
      if defined $path;    # name can be with namespace

    my $anynode = $path eq '';
    unless ($anynode) {
        if (@path) {
            return if defined $num && !$numok || !defined $num && !$nameok;
        }
        else {
            return $pointer
              if defined $num && $numok || !defined $num && $nameok;
            return;
        }
    }

    my @walk;
    push @walk, $self->_traverse_tree( [$pointer], @path ) if $anynode;
    push @walk,
      $self->_traverse_tree( o_child($pointer),
        $anynode ? ( $path, @path ) : @path );
    return @walk;
}

sub _traverse_tree {
    my $self = shift;
    my ( $pointer, @path ) = @_;

    # can be list of children or value itself. Traverse only children
    return unless ref $pointer eq 'ARRAY';

    my $itself = 1;

    grep { defined }
      map { $self->_traverse( $_, $itself++, @path ) }
      grep {
             !ref o_lattr($_)
          || !exists o_lattr($_)->{"{$SOAP::Constants::NS_ENC}root"}
          || o_lattr($_)->{"{$SOAP::Constants::NS_ENC}root"} ne '0'
      } @$pointer;
}

1;

__END__
