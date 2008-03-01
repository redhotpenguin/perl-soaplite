package SOAP::Trace;

use strict;

use Carp ();

my @list = qw(
    transport   dispatch    result
    parameters  headers     objects
    method      fault       freeform
    trace       debug);
{
    no strict 'refs';
    for (@list) {
        *$_ = sub {}
    }
}

sub defaultlog {
    my $caller = (caller(1))[3]; # the 4th element returned by caller is the subroutine namea
    $caller = (caller(2))[3] if $caller =~ /eval/;
    chomp(my $msg = join ' ', @_);
    printf STDERR "%s: %s\n", $caller, $msg;
}

sub import {
    no strict 'refs';
    local $^W;
    my $pack = shift;
    my(@notrace, @symbols);
    for (@_) {
        if (ref eq 'CODE') {
            my $call = $_;
            foreach (@symbols) { *$_ = sub { $call->(@_) } }
            @symbols = ();
        }
        else {
            local $_ = $_;
            my $minus = s/^-//;
            my $all = $_ eq 'all';
            Carp::carp "Illegal symbol for tracing ($_)" unless $all || $pack->can($_);
            $minus ? push(@notrace, $all ? @list : $_) : push(@symbols, $all ? @list : $_);
        }
    }
    # TODO - I am getting a warning here about redefining a subroutine
    foreach (@symbols) { *$_ = \&defaultlog }
    foreach (@notrace) { *$_ = sub {} }
}

1;

__END__