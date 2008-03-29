#!/bin/env perl

use strict;
use Test::More;

use lib qw(lib);

if ( not $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

eval "use Test::Strict";

SKIP: {
    skip 'You need Test::Strict installed to run strict testing', if $@;
    all_perl_files_ok(qw(t/ lib/)); # Syntax ok and use strict;
}