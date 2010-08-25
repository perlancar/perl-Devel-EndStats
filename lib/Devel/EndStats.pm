package Devel::EndStats;
# ABSTRACT: Show various statistics at the end of program run

=head1 SYNOPSIS

 # from the command line
 % perl -MDevel::EndStats script.pl

 ##### sample output #####

 # BEGIN stats from Devel::EndStats
 # Program runtime duration (s): 2
 # Total number of module files loaded: 132
 # Total number of modules lines loaded: 48772
 # END stats

 ##### sample output (with verbose=1, some cut) #####

 # BEGIN stats from Devel::EndStats
 # Program runtime duration (s): 2
 # Total number of module files loaded: 132
 # Total number of modules lines loaded: 48772
 #   Lines from Class::MOP::Class: 1733
 #   Lines from overload: 1499
 #   Lines from Moose::Util::TypeConstraints: 1390
 #   Lines from File::Find: 1349
 #   Lines from Data::Dumper: 1306
 ...
 # END stats

=head1 DESCRIPTION

Devel::EndStats runs in the END block, displaying various statistics about your
program, such as: how many seconds the program ran, how many module files and
total number of lines loaded (by inspecting %INC), etc.

Some notes/caveats:

END blocks declared after Devel::EndStats' will be executed after it, so in that
case it's ideal to load Devel::EndStats as the last module.

In modules statistics, Devel::EndStats excludes itself and the modules it uses.
Devel::EndStats tries to check whether those modules are actually loaded/used by
your program instead of just by Devel::EndStats and if so, will not exclude them.

=cut

use 5.010;

sub _inc2modname {
    local $_ = shift;
    s!/!::!g;
    s/\.pm$//;
    $_;
}

sub _mod2incname {
    local $_ = shift;
    s!::!/!g;
    "$_.pm";
}

my @my_modules = qw(
               );

my %excluded_modules;

my %opts = (
    verbose => 0,
    exclude_endstats_modules => 1,
);

=head1 OPTIONS

Some options are accepted. They can be passed via the B<use> statement:

 # from the command line
 % perl -MDevel::EndStats=verbose,1 script.pl

 # from script
 use Devel::EndStats verbose=>1;

or via the DEVELENDSTATS_OPTS environment variable:

 % DEVELENDSTATS_OPTS='verbose=1' perl -MDevel::EndStats script.pl

=over 4

=item * verbose => BOOL

Can also be set via VERBOSE environment variable. If set to true, display more
statistics (like per-module statistics). Default is 0.

=item * exclude_endstats_modules => BOOL

If set to true, exclude Devel::EndStats itself and the modules it uses from the
statistics. Default is 1.

=back

=cut

sub import {
    my ($class, %args) = @_;
    $opts{verbose} = $ENV{VERBOSE} if defined($ENV{VERBOSE});
    if ($ENV{DEVELENDSTATS_OPTS}) {
        while ($ENV{DEVELENDSTATS_OPTS} =~ /(\w+)=(\S+)/g) {
            $opts{$1} = $2;
        }
    }
    $opts{$_} = $args{$_} for keys %args;
}

INIT {
    for (qw(feature Devel::EndStats)) {
        $excluded_modules{ _mod2incname($_) }++
            if $opts{exclude_endstats_modules};
    }

    # load our modules and exclude it from stats
    for my $m (@my_modules) {
        my $im = _mod2incname($m);
        next if $INC{$im};
        my %INC0 = %INC;
        require $im;
        if ($opts{exclude_endstats_modules}) {
            for (keys %INC) {
                $excluded_modules{$_}++ unless $INC0{$_};
            }
        }
    }
}

END {
    print STDERR "\n";
    print STDERR "# BEGIN stats from Devel::EndStats\n";

    print STDERR sprintf "# Program runtime duration (s): %d\n", (time() - $^T);

    my $modules = 0;
    my $lines = 0;
    my %lines;
    local *F;
    for my $im (keys %INC) {
        next if $excluded_modules{$im};
        $modules++;
        $lines{$im} = 0;
        next unless $INC{$im}; # undefined in some cases
        open F, $INC{$im} or next;
        while (<F>) { $lines++; $lines{$im}++ }
    }
    print STDERR sprintf "# Total number of module files loaded: %d\n", $modules;
    print STDERR sprintf "# Total number of modules lines loaded: %d\n", $lines;
    if ($opts{verbose}) {
        for my $im (sort {$lines{$b} <=> $lines{$a}} keys %lines) {
            print STDERR sprintf "#   Lines from %s: %d\n", _inc2modname($im), $lines{$im};
        }
    }

    print STDERR "# END stats\n";
}

=head1 FAQ

=head2 What is the purpose of this module?

This module might be useful during development. I first wrote this module when
trying to reduce startup overhead of a command line application, by looking at
how many modules the app has loaded and try to avoid loading modules whenever
it's unnecessary.

=head2 Can you add (so and so) information to the stats?

Sure, if it's useful. As they say, (comments|patches) are welcome.

=head1 SEE ALSO

=head1 TODO

* Stat: memory usage.

* Subsecond program duration.

* Stat: system/user time.

* Stat: number of open files (sockets).

* Stat: number of child processes.

* Stat: number of XS vs PP modules.

* Feature: remember last run's stats, compare with current run.

=cut

1;
