#!/usr/bin/perl -w
use Devel::Leak;
use SOAP::Lite;
my $endpoint = 'http://localhost/Authentication_test.php';
my $table;
my $count = Devel::Leak::NoteSV($table);

for (1..11) {
    my $soap     = SOAP::Lite->new()
      ->proxy($endpoint);
    print "# SV count: ", Devel::Leak::NoteSV($table), "\n";
}
