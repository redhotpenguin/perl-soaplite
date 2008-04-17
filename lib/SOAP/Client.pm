package SOAP::Client;

use strict;

use vars qw($VERSION);
use SOAP::Lite::Utils;

use version; $VERSION = qv(0.71.03);

sub BEGIN {
    __PACKAGE__->__mk_accessors(qw(endpoint code message
        is_success status options));
}

1;

__END__