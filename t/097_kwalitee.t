#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

if ( not $ENV{AUTHOR_TESTING} ) {
    my $msg = 'Author test.  Set $ENV{AUTHOR_TESTING} to a true value to run.';
    plan( skip_all => $msg );
}

chdir '..' if -d ('../t');

eval 'use Test::Kwalitee';

if ( $@ ) {
    my $msg = 'Test::Kwalitee not installed; skipping';
    plan( skip_all => $msg );
}
