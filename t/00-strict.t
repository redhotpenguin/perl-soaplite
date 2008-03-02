#!/bin/env perl 

use strict;
use Test::More q(no_plan);

BEGIN {
  unless(grep /blib/, @INC) {
    chdir 't' if -d 't';
    unshift @INC, '../lib' if -d '../lib';
    push @INC, 'lib/';
  }
}

eval "use Test::Strict";

SKIP: {
    skip 'You need Test::Strict installed to run strict testing', if $@;
    all_perl_files_ok('../lib/','../t','t/','lib/'); # Syntax ok and use strict;
}