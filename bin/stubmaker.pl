#!/bin/env perl 
#!d:\perl\bin\perl.exe 
#
# Filename: stubmaker.pl
# Authors: Byrne Reese <byrne at majordojo dot com>
#          Paul Kulchenko
#
# Copyright (C) 2001 Paul Kulchenko --
#
# Usage:
#    stubmaker.pl -[vd] <WSDL URL>
###################################################

use SOAP::Lite;
use Getopt::Long;

my $VERBOSE = 0;
my $DIRECTORY = ".";
GetOptions(
	   'd=s' => \$DIRECTORY,
	   'v' => \$VERBOSE,
	   help => sub { HELP_MESSAGE(); },
	   version => sub { VERSION_MESSAGE(); exit(0); },
	   ) or HELP_MESSAGE();

HELP_MESSAGE() unless $ARGV[0];

my $WSDL_URL = shift;

print "Writing stub files...\n" if $VERBOSE;
my %services = %{SOAP::Schema->schema_url($WSDL_URL)
                             ->cache_dir($DIRECTORY)
                             ->parse()
                             ->load
                             ->services};
Carp::croak "More than one service in service description. Service and port names have to be specified\n" 
    if keys %services > 1; 

sub VERSION_MESSAGE {
    print "$0 $SOAP::Lite::VERSION (C) 2005 Byrne Reese.\n";
}

sub HELP_MESSAGE {
    VERSION_MESSAGE();
    print <<EOT;
usage: $0 -[options] <WSDL URL>
options:
  -v             Verbose Outputbe quiet
  -d <dirname>   Output directory
EOT
exit 0;
}

__END__

=pod

=head1 NAME

stubmaker.pl - Generates client stubs from a WSDL file.

=head1 OPTIONS

=over

=item -d <dirname>

Specifies the directory you wish to output the files to. The directory must already exist.

=item -v

Turns on "verbose" output during the code stub generation process. To be honest, there is not much the program outputs, but if you must see something output to the console, then this fits the bill.

=item --help

Outputs a short help message.

=item --version

Outputs the current version of stubmaker.pl.

=cut

=head1 EXAMPLES

Try the following:
> perl stubmaker.pl http://www.xmethods.net/sd/StockQuoteService.wsdl

Or:
> perl "-MStockQuoteService qw(:all)" -le "print getQuote('MSFT')" 

=head1 COPYRIGHT

TODO
