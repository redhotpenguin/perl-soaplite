#!/bin/env perl 

use strict;
use Test::More q(no_plan);

use lib qw(lib);

eval "use Test::Strict";

SKIP: {
    skip 'You need Test::Strict installed to run strict testing', if $@;
    all_perl_files_ok(qw(t/ lib/)); # Syntax ok and use strict;
}