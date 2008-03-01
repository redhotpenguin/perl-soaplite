package SOAP::Server::Parameters;

use strict;

sub byNameOrOrder {
    unless (UNIVERSAL::isa($_[-1] => 'SOAP::SOM')) {
        warn "Last parameter is expected to be envelope\n" if $^W;
        pop;
        return @_;
    }
    my $params = pop->method;
    my @mandatory = ref $_[0] eq 'ARRAY'
        ? @{shift()}
        : die "list of parameters expected as the first parameter for byName";
    my $byname = 0;
    my @res = map { $byname += exists $params->{$_}; $params->{$_} } @mandatory;
    return $byname
        ? @res
        : @_;
}

sub byName {
  unless (UNIVERSAL::isa($_[-1] => 'SOAP::SOM')) {
    warn "Last parameter is expected to be envelope\n" if $^W;
    pop;
    return @_;
  }
  return @{pop->method}{ref $_[0] eq 'ARRAY' ? @{shift()} : die "list of parameters expected as the first parameter for byName"};
}

1;

__END__