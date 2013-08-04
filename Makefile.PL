#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

my %prereqs = (
    "Test::More"       => 0,
    "XML::Parser"      => "2.23",
    "MIME::Base64"     => 0,
    "URI"              => 0,
    "IO::SessionData"  => 1.03,
    "Scalar::Util"     => 0,
    "Task::Weaken"     => 0,         # to be sure than weaken works
    "constant"         => 0,         # don't force people to upgrade
    "Class::Inspector" => 0,
    "LWP::UserAgent"   => 0,
    "Crypt::SSLeay"    => 0,
    "MIME::Lite"       => 0,
    "HTTP::Daemon"     => 0,
    "MIME::Parser"     => 0,
    "IO::File"         => 0,
    "MIME::Parser"     => 0,
    "IO::Scalar"       => "2.105",
    "Data::UUID"       => "0.11",
    "IO::Socket::SSL"  => 0,
    "Compress::Zlib"   => 0,
);

ExtUtils::MakeMaker::WriteMakefile(
    'NAME' => 'SOAP::Lite',
    'AUTHOR' =>
'Pavel Kulchenko, Randy J Ray, Byrne Reese, Martin Kutter (MKUTTER@cpan.org), Fred Moyer',
    'LICENSE'       => 'perl',
    'VERSION_FROM'  => 'lib/SOAP/Lite.pm',
    'ABSTRACT_FROM' => 'lib/SOAP/Lite.pm',
    'PREREQ_PM'     => \%prereqs,
    'EXE_FILES' => [ 'bin/SOAPsh.pl', 'bin/XMLRPCsh.pl', 'bin/stubmaker.pl' ],
    (
        $ExtUtils::MakeMaker::VERSION ge '6.48'
        ? (
            MIN_PERL_VERSION => 5.006,
            META_MERGE       => {
                resources => {
                    repository => 'https://github.com/redhotpenguin/soaplite',
                },
                keywords => [ 'SOAP', 'SOAP client', 'SOAP server' ],

            },
          )
        : ()
    ),
);

1;
