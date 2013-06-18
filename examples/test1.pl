#!/usr/bin/perl

use strict;

my $foo;
my $foo2;

if ( $foo )
{
    print "bar\n";
}

print STDERR "THIS IS A BUG\n";

print 2+2, "\n";
