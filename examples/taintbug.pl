#!/usr/bin/env perl -T
# without Taint there is no bug


use strict;
use warnings;

#warn "THIS REPLICATES THE BUG\n";warn $_ for %INC;

#{
    
#NOBUG without $ua                      ##### # # # # 
    use WWW::Mechanize;
    my $ua = WWW::Mechanize->new();

    my $url = shift;

    die "add file:taintbug.html to the command line" unless $url and length $url and $url =~ m!taint.*?(\w).(\w)!i ;

    $ua->get($url);

    my $pager = parsepage($ua);
    warn;
#}
exit(0);

sub parsepage {
    my $ua = shift;
    my %so;
    my $so = join "\n", $ua->content =~/(so\.addVariable\(\s*'.+?'\s*,\s*'.+?'\s*\)\s*;)/mg;
    warn $so;
#    warn; #    Insecure dependency in kill while running with -T switch at C:/Perl/site/lib/WWW/Mechanize.pm line 2326.
#Faulting application perl.exe, version 5.8.9.825, faulting module msvcrt.dll, version 7.0.2600.1106, fault address 0x00033283.
#    111111111111111111111111111111111111111111111111111111111111111111 1
    while($so =~/so\.addVariable\('([^']+)','([^']+)'\);/mg) {
        warn "b $1 $2";
        $so{"$1"}="$2";
        warn "a $1 $2";
    }

    require CGI;
    return CGI->new({%so});
}


__END__
