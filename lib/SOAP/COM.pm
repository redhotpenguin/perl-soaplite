package SOAP::Lite::COM;

use strict;

require SOAP::Lite;

sub required {
  foreach (qw(
    URI::_foreign URI::http URI::https
    LWP::Protocol::http LWP::Protocol::https LWP::Authen::Basic LWP::Authen::Digest
    HTTP::Daemon Compress::Zlib SOAP::Transport::HTTP
    XMLRPC::Lite XMLRPC::Transport::HTTP
  )) {
    eval join ';', 'local $SIG{__DIE__}', "require $_";
  }
}

sub new    { required; SOAP::Lite->new(@_) }

sub create; *create = \&new; # make alias. Somewhere 'new' is registered keyword

sub soap; *soap = \&new;     # also alias. Just to be consistent with .xmlrpc call

sub xmlrpc { required; XMLRPC::Lite->new(@_) }

sub server { required; shift->new(@_) }

sub data   { SOAP::Data->new(@_) }

sub header { SOAP::Header->new(@_) }

sub hash   { +{@_} }

sub instanceof {
  my $class = shift;
  die "Incorrect class name" unless $class =~ /^(\w[\w:]*)$/;
  eval "require $class";
  $class->new(@_);
}

1;

__END__