package SOAP;

use strict;

use vars qw($AUTOLOAD);
require URI;

our $soap; # shared between SOAP and SOAP::Lite packages

{
    no strict 'refs';
    *AUTOLOAD = sub {
        local($1,$2);
        my($package, $method) = $AUTOLOAD =~ m/(?:(.+)::)([^:]+)$/;
        return if $method eq 'DESTROY';

        my $soap = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $_[0]
            : $soap
                || die "SOAP:: prefix shall only be used in combination with +autodispatch option\n";

        my $uri = URI->new($soap->uri);
        my $currenturi = $uri->path;
        $package = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $currenturi
            : $package eq 'SOAP'
                ? ref $_[0] || ($_[0] eq 'SOAP'
                    ? $currenturi || Carp::croak "URI is not specified for method call"
                    : $_[0])
                : $package eq 'main'
                    ? $currenturi || $package
                    : $package;

        # drop first parameter if it's a class name
        {
            my $pack = $package;
            for ($pack) { s!^/!!; s!/!::!g; }
            shift @_ if @_ && !ref $_[0] && ($_[0] eq $pack || $_[0] eq 'SOAP')
                || ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite');
        }

        for ($package) { s!::!/!g; s!^/?!/!; }
        $uri->path($package);

        my $som = $soap->uri($uri->as_string)->call($method => @_);
        UNIVERSAL::isa($som => 'SOAP::SOM')
            ? wantarray
                ? $som->paramsall
                : $som->result
            : $som;
    };
}

1;

__END__