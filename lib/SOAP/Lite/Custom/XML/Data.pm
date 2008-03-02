package SOAP::Lite::Custom::XML::Data;

use strict;

use vars qw(@ISA $AUTOLOAD);
@ISA = qw(SOAP::Data);

use overload fallback => 1, '""' => sub { shift->value };

sub _compileit {
    no strict 'refs';
    my $method = shift;
    *$method = sub {
        return __PACKAGE__->SUPER::name($method => $_[0]->attr->{$method})
            if exists $_[0]->attr->{$method};
        my @elems = grep {
            ref $_ && UNIVERSAL::isa($_ => __PACKAGE__)
            && $_->SUPER::name =~ /(^|:)$method$/
        } $_[0]->value;
        return wantarray? @elems : $elems[0];
    };
}

sub BEGIN { foreach (qw(name type import use)) { _compileit($_) } }

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    _compileit($method);
    goto &$AUTOLOAD;
}

1;

__END__