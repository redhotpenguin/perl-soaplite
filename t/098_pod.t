use strict;
use Test::More;

if ( not $ENV{AUTHOR_TESTING} ) {
    my $msg = 'Author test.  Set $ENV{AUTHOR_TESTING} to a true value to run.';
    plan( skip_all => $msg );
}

eval "use Test::Pod 1.00";
if ($@) { 
    print "# Test::Pod 1.00 required for testing POD";
    plan(tests => 0);
    exit 0;
}

my @directories;

# perl Build test or make test run from top-level dir. 
if ( -d '../t/' ) {
    @directories = ('../lib/', '../bin');
}
else {
    @directories = (); # empty - will work automatically
}

my @files = all_pod_files(@directories);

plan(tests => scalar(@files) );

foreach my $module (@files){
    pod_file_ok( $module )
}
