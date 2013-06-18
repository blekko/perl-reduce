#!/usr/bin/env perl

# https://rt.perl.org/rt3/Ticket/Display.html?id=34035

# unfortunately this segfaults 5.8.[56], which isn't easily available in perlbrew
# perl-5.6.2 (which is available in perlbrew) doesn't like the syntax. might be a flaw in my perlbrew env.

use strict;
use warnings;

use constant {
_OP_ARGS => 0,
_OP_NEXT => 1,
};

sub match_string {
my ($program) = @_;

my $ip = 0;

FORWARD:
while ($ip >= 0) {
my $op = $$program[$ip];

my $val = $$op[_OP_ARGS];
# changing the condition to 0 fixes the segfault
unless (substr('hallf', 0, length $val) eq $val) {
print ">$op<\n";
goto BACKTRACK;
}

next; # also commenting this fixes it

BACKTRACK:
print ">$op<\n";
#die;

} continue { # and commenting this whole continue block fixes it
$ip = $$program[$ip][_OP_NEXT];
}
}

match_string([['hal', 1], ['f', -1]]);
