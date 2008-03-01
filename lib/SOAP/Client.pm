package SOAP::Client;

use strict;

use vars qw($VERSION);
use SOAP::Lite::Utils;

$VERSION = '0.70';
sub BEGIN {
    __PACKAGE__->__mk_accessors(qw(endpoint code message
        is_success status options));
}

1;

__END__