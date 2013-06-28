#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw( :config require_order );

my %opt;

my %options = (
               'keep'       => \$opt{keep},
               'quiet'      => \$opt{quiet},
               'timeout=s'  => \$opt{timeout},
               'valgrind'   => \$opt{valgrind},
               'taint'      => \$opt{taint},
               'perl=s'     => \$opt{perl},
               'stdout=s'   => \$opt{stdout},
               'stderr=s'   => \$opt{stderr},
               'signal=s'   => \$opt{signal},
               'o|output=s' => \$opt{output},
               'test'       => \$opt{test},
              );

GetOptions ( %options );

run_tests() if $opt{test};

if ( ! defined $opt{timeout} )
{
    $opt{timeout} = $opt{valgrind} ? 120 : 3;
}
$opt{perl} = "perl" if ! defined $opt{perl};

my $file = shift || die "usage: perl-reduce script args ...";

print "Command run will be: $file ", join( ' ', @ARGV ), "\n";

$ENV{LIBC_FATAL_STDERR_} = 1; # damn you glibc

my $script = deparse_script( $file );

my $round = 1;

while ( 1 )
{
    print "Round $round, begin.\n";
    $script = preprocess_loop( $script );
    keep_file( $script, "round $round initial candidate", nosuffix => 1 ) if $opt{keep};

    print "Round $round, syntax test initial candidate\n";
    my $initial = [ { c => $script, line => 999_999 } ];
    die "round $round initial candidate has invalid syntax" if ! @{syntax_check_candidates( $initial )};
    print "Round $round, bug test initial candidate\n";
    die "round $round initial candidate does not show the bug" if ! @{find_bug( $initial, \@ARGV )};

    my $candidates = generate_candidates( $script );
    print "Round $round, ", scalar @$candidates, " candidates.\n";

    my $valid_candidates = syntax_check_candidates( $candidates );
    print "Round $round, ", scalar @$valid_candidates, " valid candidates.\n";

    if ( @$valid_candidates < 1 )
    {
        print "Round $round. No valid candidates.\n";
        keep_file( $script, $opt{output}, nosuffix => 1 );
        exit 0;
    }

    my $buggy = find_bug( $valid_candidates, \@ARGV );
    print "Round $round, ", scalar @$buggy, " buggy candidates.\n";

    if ( @$buggy < 1 )
    {
        print "Round $round. No buggy candidates.\n";
        keep_file( $script, $opt{output}, nosuffix => 1 );
        exit 0;
    }

    $script = generate_accelerated_candidate( $script, $buggy );
    keep_file( $script, "round $round final accelerated candidate", nosuffix => 1 ) if $opt{keep};

    my $acc = [ { c => $script, line => 999_999 } ];

    if ( @{syntax_check_candidates( $acc )} && @{find_bug( $acc, \@ARGV )} )
    {
        print "Round $round, hooray! The acceleration algorithm worked!\n";
    }
    else
    {
        print "Acceleration failed. Quitting because I do not know how to proceed non-accelerated.\n";
        keep_file( $script, $opt{output}, nosuffix => 1 );
        exit 1;
    }

    $round++;
}

sub generate_accelerated_candidate
{
    my ( $script, $buggy ) = @_;

    my @ret = split /\n/, $script;

    print " Lines to remove: ", join( ",", map { $_->{line} } @$buggy ), "\n";

    foreach my $b ( @$buggy )
    {
        my ( $l, $what ) = $b->{line} =~ / ^ (\d+) (?:\s (\S+))? $ /x;

        if ( ! defined $what )
        {
            $ret[$l] = undef;
        }
        elsif ( $what eq 'next' )
        {
            $ret[$l] = undef;
            $ret[$l+1] = undef;
        }
        elsif ( $what eq 'semi' )
        {
            $ret[$l] = ';';
        }
    }

    return join( "\n", grep { defined $_ } @ret );
}

sub generate_candidates
{
    my ( $script ) = @_;

    my @lines = split /\n/, $script;
    my @candidates;

    for my $l ( 0 .. $#lines )
    {
        if ( is_eligible( $lines[$l] ) )
        {
            my @copy = @lines;

            $copy[$l] = ';';
            my $c2 = join "\n", @copy;

            $copy[$l] = undef;
            my $c1 = join "\n", grep { defined $_ } @copy;

            $copy[$l + 1] = undef;
            my $c3 = join "\n", grep { defined $_ } @copy;

            push @candidates, { line => $l, c1 => $c1, c2 => $c2, c3 => $c3 };
        }
    }
    return ( \@candidates );
}

sub syntax_check_candidates
{
    my ( $candidates ) = @_;
    my @valid_candidates;

    my $count = 0;
    my $win = 0;
    my @cmd;
    push @cmd, $opt{perl}, "-c";
    push @cmd, "-T" if $opt{taint};
    push @cmd, "tmp.pl";

    foreach my $c ( @$candidates )
    {
        print "\r$win / $count" if ! $opt{quiet};
        $count++;

        my $cand = $c->{c1} || $c->{c};

        my ( $signal, $ret ) = run_one( $cand, @cmd );

        if ( ! $ret )
        {
            push @valid_candidates, { c => $cand, line => $c->{line} };
            keep_file( $cand, "round-$round-passed-perl-c" ) if $opt{keep};
            $win++;
            next;
        }
        keep_file( $cand, "round-$round-failed-perl-c" ) if $opt{keep};

        next if ! $c->{c2};

        ( $signal, $ret ) = run_one( $c->{c2}, @cmd );

        if ( ! $ret )
        {
            push @valid_candidates, { c => $c->{c2}, line => "$c->{line} semi" };
            keep_file( $c->{c2}, "round-$round-passed-perl-c-semi" ) if $opt{keep};
            $win++;
            next;
        }
        keep_file( $c->{c2}, "round-$round-failed-perl-c-semi" ) if $opt{keep};

        next if ! $c->{c3};

        ( $signal, $ret ) = run_one( $c->{c3}, @cmd );

        if ( ! $ret )
        {
            push @valid_candidates, { c => $c->{c3}, line => "$c->{line} next" };
            keep_file( $c->{c3}, "round-$round-passed-perl-c-next" ) if $opt{keep};
            $win++;
            next;
        }
        keep_file( $c->{c3}, "round-$round-failed-perl-c-next" ) if $opt{keep};
    }
    print "\r$win / $count\n";

    return \@valid_candidates;
}

sub find_bug
{
    my ( $candidates, $args ) = @_;
    my @buggy;

    my $count;
    my $win = 0;
    my @cmd;
    push @cmd, $opt{perl};
    unshift @cmd, "valgrind" if $opt{valgrind};
    push @cmd, "-T" if $opt{taint};
    push @cmd, "tmp.pl";

    foreach my $c ( @$candidates )
    {
        $count++;

        my ( $signal, $ret, $stdout, $stderr ) = run_one( $c->{c}, @cmd, @$args );

        my $fail;
        $fail = 1 if $opt{stderr} && $stderr =~ /$opt{stderr}/;
        $fail = 1 if $opt{stdout} && $stdout =~ /$opt{stdout}/;
        $fail = 1 if $opt{signal} && $signal == $opt{signal}; # signal != 0 case
        $fail = 1 if defined $opt{signal} && $opt{signal} == 0 && $signal;

        if ( $signal && ! $fail )
        {
            warn "Saw signal=$signal"; # a different bug than what we were looking for. be loud.
            keep_file( $c->{c}, "round-$round-got-signal-$signal" );
        }

        if ( $fail )
        {
            push @buggy, $c;
            keep_file( $c->{c}, "round-$round-was-a-bug" ) if $opt{keep} && $c->{line} ne '999999';
            $win++;
        }
        else
        {
            keep_file( $c->{c}, "round-$round-was-not-a-bug" ) if $opt{keep} && $c->{line} ne '999999';
        }
        print "\r$win / $count" if ! $opt{quiet};
    }
    print "\r$win / $count\n";

    return \@buggy;
}

sub run_one
{
    my ( $candidate, @cmd ) = @_;

    $candidate = '' if ! defined $candidate; # yeah, it can arrive undef. let's process it anyway.

    open my $fd, ">", "tmp.pl" or die "can't open tmp.pl for writing: $!";
    print $fd "$candidate\n";
    close $fd or die "error closing tmp.pl: $!";

    my $status;
    my $timed_out;
    my $command = join ' ', @cmd; # just for printing

    my $pid = fork;
    if ( ! defined $pid )
    {
        die "fork failed: $!";
    }

    if ( $pid ) # parent
    {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
        alarm $opt{timeout};
        eval {
            waitpid $pid, 0;
            $status = $?;
        };
        if ( $@ ) # alarm fired
        {
            print "\ntimeout; sending kill signal to pid=$pid\n";
            kill 9, $pid;
            # XXX this leaves $pid as a zombie. needs a waitpid
            $timed_out = 1;
            $status = 128;
        }
        alarm 0;
    }
    else # child
    {
        unlink( "STDOUT" );
        unlink( "STDERR" );
        open STDOUT, ">", 'STDOUT' or warn "redirecting STDOUT to file: $!";
        open STDERR, ">", 'STDERR' or warn "redirecting STDERR to file: $!";

        # XXX set parent death here

        exec( @cmd );

        die "exec of <$command> failed: $!";
    }

    die "Error running $command: $!" if $status == -1;

    my $signal = $status & 127;
#    die "Got signal=$signal running $command" if $signal;

    my $ret = $status >> 8;
    $ret = -1 if $timed_out;

    my $stdout = '';
    $stdout = `cat STDOUT` if -f "STDOUT";
    unlink( "STDOUT" );

    my $stderr = '';
    $stderr = `cat STDERR` if -f "STDERR";
    unlink( "STDERR" );

    unlink( "tmp.pl" );

    return ( $signal, $ret, $stdout, $stderr );
}

sub deparse_script
{
    my ( $file ) = @_;
    my $taint = $opt{taint} ? "-T" : "";

    my $cmd = "$opt{perl} -MO=Deparse $taint -sc $file"; # -sc = cuddle else/elsif/continue

    my $ret = `$cmd`;
    die "Error running deparse on $file" if $?;

    return $ret;
}

#sub read_script
#{
#    my ( $file ) = @_;
#    my $ret;
#    my $in_pod = 0;
#
#    open my $fd, "<", $file or die "Error opening $file: $!";
#    while ( <$fd> )
#    {
#       chomp;
#
#       s/^\s*\#.*// if $_ !~ m,^\#\!,; # delete line-starting comments but leave shebang
#
#       s/\s+\#.*//; # remove mid-line # only if preceeded by a space -- will catch things like m/ #/ tho XXX
#
#       if ( /^=cut$/ )
#       {
#           $in_pod = 0;
#           next;
#       }
#       $in_pod = 1 if /^=head\d/;
#       next if $in_pod;
#
#       next if $_ =~ /^\s*$/; # skip empty lines
#
#       $ret .= "$_\n";
#    }
#    close $fd;
#
#    return $ret;
#}

sub is_eligible
{
    my ( $line ) = @_;

    # shebang
    return if $line =~ / ^ \# \! /x;

    # strict helps provide much better syntax checking, so keep it (but not warnings)
    return if $line =~ / ^ \s* use \s+ strict /x;
    return if $line =~ / ^ \s* no \s+ strict /x;

    # can't get rid of package lines until empty
    return if $line =~ / ^ \s* package \s /x;

    # keep line-starting naked } )
    return if $line =~ / ^ \s* [\}\)] /x;

    # keep line-ending naked { (
    return if $line =~ / [\{\(] \s* $ /x;

    return 1;
}

sub preprocess_loop
{
    # XXX to be honest, I'm not sure this needs to be a loop.

    my ( $script ) = @_;

    my $count = 1;
    while ( 1 )
    {
        my $new_script = preprocess( $script );
        my @lines = $new_script =~ /\n/g;
        print "Preprocessed and ended up with ", scalar @lines, " lines\n";
        last if $script eq $new_script; # no change
        $script = $new_script;
        keep_file( $script, "round $round preprocess after count=$count" ) if $opt{keep};
        $count++;
    }
    print "Preprocessing finished after $count loops\n";

    return $script;
}

sub preprocess
{
    my ( $script ) = @_;
    my @ret;
    my $previous_joiner;

    my $first_strict = 1;
    my $last_was_package = 0;
    my $in_data = 0;

    foreach my $l ( split /\n/, $script )
    {
        if ( $in_data )
        {
            push @ret, $l;
            next;
        }

        if ( $l =~ /^__DATA__$/ )
        {
            $in_data = 1;
            push @ret, $l;
            next;
        }

        # discard eol spaces
        $l =~ s/ \s+ $ //x;

        if ( $l =~ m/ \s* package \s /x )
        {
            if ( $last_was_package )
            {
                pop @ret;
            }
            $last_was_package = 1;
        }
        else
        {
            $last_was_package = 0;
        }

        if ( $l =~ m/ \s* use \s+ strict/x )
        {
            next if ! $first_strict;
            $first_strict = 0;
        }

        if ( $previous_joiner )
        {
            $l =~ s/ ^ \s+ //x;
            $ret[-1] .= " $l";
            $previous_joiner = undef;
            next;
        }

        # list of things starting lines that we unconditionally join with the previous line
        if ( $l =~ / ^ \s* ( \: | \? | \; | \| | \& | \+[^\+] | \-[^\-] | \/ | \* | \. | \, | and | or | not | xor | else | elsif | continue ) /x )
        {
            $l =~ s/ ^ \s+ //x;
            $ret[-1] .= " $l";
            $previous_joiner = undef;
            next;
        }

        # list of things ending lines that we unconditionally join with the next line
        if ( $l =~ / ( \: | \? | \| | \& | \+ | \- | \* | \. | \> | and | or | not | xor ) $ /x ) # \/
        {
            $previous_joiner = 1;
            push @ret, $l;
            next;
        }

        $previous_joiner = undef;

        push @ret, $l;
    }

    # git rid of package lines at the end of the script
    pop @ret if $ret[-1] =~ / ^ \s* package \s /xms;

    my $s = join "\n", @ret;

    # now a few rules that are not line-by-line

    # empty block
    $s =~ s/  { \s* }  /{ }/xmsg;
    $s =~ s/ \( \s* \) /( )/xmsg;

    # empty block with semicolon
    $s =~ s/ { \s* ; \s* } /{ ; }/xmsg;

    return $s;
}

my $suffix;

sub keep_file
{
    my ( $data, $name, %opts ) = @_;

    if ( ! defined $name )
    {
        print "$data\n";
        return;
    }

    if ( ! defined $opts{nosuffix} )
    {
        $suffix = 0 if ! defined $suffix;
        $name .= " $suffix";
        $suffix++;
    }
    $name =~ s/ /-/g;
    open my $fd, ">", $name or die "can't open $name: $!";

    print $fd "$data\n";
    close $fd or die "error closing $name: $!";
}

sub system_with_timeout
{
    my ( $timeout, @argv ) = @_;

    my $status = 1;
    return 1 unless defined $timeout and $timeout > 0;
    return 1 unless @argv and "@argv";

    my $pid = fork;
    if ( ! defined $pid )
    {
        die "fork failed: $!";
    }

    if ( $pid ) # parent
    {
        local $SIG{ALRM} = sub { die "Alarm fired\n"; }; # nb \n is required
        alarm $timeout;
        eval {
            waitpid $pid, 0;
            $status = $?;
        };
        if ( $@ ) # alarm fired
        {
            kill 9, $pid;
            return $status || 1; # force it to non-zero
        }
        alarm 0;
    }
    else
    {
        open STDOUT, ">", 'STDOUT' or warn "redirecting STDOUT to file: $!";
        open STDERR, ">", 'STDERR' or warn "redirecting STDERR to file: $!";
        exec @argv;
        die "exec failed: $!";
    }
    return $status;
}

sub run_tests
{
    my @preprocess_tests = (
                            [ "package  Foo;    \n package Bar;\nfoo\n", " package Bar;\nfoo", "package" ],
                            [ "package  Foo;    \n package Bar;\n", "", "package end" ],
                            [ "use strict;  \n use strict;", "use strict;", "strict" ],
                            [ "foo xor\nbar", "foo xor bar", "previous joiner" ],
                            [ "sub {\nfoo;\n}\n,", "sub {\nfoo;\n} ,", "previous joiner, common B::Deparse issue" ],
                            [ "foo \n  and", "foo and", "next joiner" ],
                            [ "sub foo {\n}\n", "sub foo { }", "empty block" ],
                            [ "foo {\n  }", "foo { }", "empty block indented" ],
                            [ "foo {\n;\n }", "foo { ; }", "empty block semicolon" ],
                            [ "if ( \$sort_sub ) { } else {\n}", "if ( \$sort_sub ) { } else { }", "if then else empty block" ],
                            [ "do {\n  qr/\$regex/\n  }", "do {\n  qr/\$regex/\n  }", "block with single non-semi statement" ],
                            [ "foo;\n__DATA__\nexactly this  \nand\n this ", "foo;\n__DATA__\nexactly this  \nand\n this ", "__DATA__ section" ],
                           );

    use Test::More tests => 12;

    foreach my $t ( @preprocess_tests )
    {
        my ( $i, $o, $s ) = @$t;
        is( preprocess( $i ), $o, "preprocess: $s" );
    }

    exit 0;
}
