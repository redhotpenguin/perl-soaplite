#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

if ( not $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

chdir '..' if -d ('../t');

{
    # Test::Kwalitee complains when AUTHOR_TESTING or RELEASE_TESTING is not
    # set. Since this test file is already guarded by TEST_AUTHOR, it's fine to
    # just set either of required env. var.
    local $ENV{AUTHOR_TESTING} = 1;
    eval 'use Test::Kwalitee';
}

if ( $@ ) {
    my $msg = 'Test::Kwalitee not installed; skipping';
    plan( skip_all => $msg );
}
