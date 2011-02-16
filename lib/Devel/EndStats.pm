package Devel::EndStats;
# ABSTRACT: Show various statistics at the end of program run

=head1 SYNOPSIS

 # from the command line
 % perl -MDevel::EndStats script.pl

 ##### sample output #####
 <normal script output, if any...>

 # BEGIN stats from Devel::EndStats
 # Program runtime duration (s): 2
 # Total number of required files loaded: 132
 # Total number of required lines loaded: 48772
 # END stats

 ##### sample output (with verbose=1, some cut) #####
 <normal script output, if any...>

 # BEGIN stats from Devel::EndStats
 # Program runtime duration (s): 2
 # Total number of required files loaded: 132
 # Total number of required lines loaded: 48772
 #   Lines from Class::MOP::Class: 1733
 #   Lines from overload: 1499
 #   Lines from Moose::Util::TypeConstraints: 1390
 #   Lines from File::Find: 1349
 #   Lines from Data::Dumper: 1306
 ...
 # END stats

=head1 DESCRIPTION

Devel::EndStats runs in the END block, displaying various statistics about your
program, such as:

=over 4

=item * how many seconds the program ran;

=item * how many required files and total number of lines loaded (from %INC);

=item * etc.

=back

Some notes/caveats:

Devel::EndStats should be loaded before other modules.

=cut

use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);

my %excluded;

our %opts = (
    verbose      => 0,
    _quiet       => 0,
);

=head1 OPTIONS

Some options are accepted. They can be passed via the B<use> statement:

 # from the command line
 % pZerl -MDevel::EndStats=verbose,1 script.pl

 # from script
 use Devel::EndStats verbose=>1;

or via the DEVELENDSTATS_OPTS environment variable:

 % DEVELENDSTATS_OPTS='verbose=1' perl -MDevel::EndStats script.pl

=over 4

=item * verbose => BOOL

Can also be set via VERBOSE environment variable. If set to true, display more
statistics (like per-module statistics). Default is 0.

=back

=for Pod::Coverage handler

=cut

sub handler {
    my ($coderef, $filename) = @_;
    my $load = 1;

    # XXX intercept lib.pm so we still stay as the first item in @INC
    if ($filename eq 'lib') {
        $load = 0;
        # ...
    }

    # search and load file, based on rest of @INC

    #print "DEBUG: Loading $filename ...\n";
    #return (undef, sub {return 0});

    #return (\*FH, );
}

my @start_time;
sub import {
    my ($class, %args) = @_;
    $opts{verbose} = $ENV{VERBOSE} if defined($ENV{VERBOSE});
    if ($ENV{DEVELENDSTATS_OPTS}) {
        while ($ENV{DEVELENDSTATS_OPTS} =~ /(\w+)=(\S+)/g) {
            $opts{$1} = $2;
        }
    }
    $opts{$_} = $args{$_} for keys %args;
    #unshift @INC, \&handler;
    @start_time = gettimeofday();
}

my $begin_success;
{
    # shut up warning about too late to run INIT block
    no warnings;
    INIT {
        # exclude modules which we use ourselves
        for (
            "strict.pm",
            "Devel/EndStats.pm",
            "warnings.pm",
            "warnings/register.pm",

            # from Time::HiRes
            "AutoLoader.pm",
            "Config_git.pl",
            "Config_heavy.pl",
            "Config.pm",
            "DynaLoader.pm",
            "Exporter/Heavy.pm",
            "Exporter.pm",
            "Time/HiRes.pm",
            "vars.pm",
        ) {
            $excluded{$_}++;
        }
        $begin_success++;
    }
}

our $stats;
END {
    my $secs = tv_interval(\@start_time);

    $stats  = "\n";
    $stats .= "# BEGIN stats from Devel::EndStats\n";

    if ($begin_success) {

        $stats .= sprintf "# Program runtime duration (s): %.3fs\n", $secs;

        my $files = 0;
        my $lines = 0;
        my %lines;
        local *F;
        for my $r (keys %INC) {
            next if $excluded{$r};
            $files++;
            $lines{$r} = 0;
            next unless $INC{$r}; # undefined in some cases
            open F, $INC{$r} or do {
                warn "Devel::EndStats: Can't open $INC{$r}, skipped\n";
                next;
            };
            while (<F>) { $lines++; $lines{$r}++ }
        }
        $stats .= sprintf "# Total number of required files loaded: %d\n",
            $files;
        $stats .= sprintf "# Total number of required lines loaded: %d\n",
            $lines;
        if ($opts{verbose}) {
            for my $r (sort {$lines{$b} <=> $lines{$a}} keys %lines) {
                $stats .= sprintf "#   Lines from %s: %d\n", $r, $lines{$r};
            }
        }

    } else {

        $stats .= "# BEGIN phase didn't succeed?\n";

    }

    $stats .= "# END stats\n";
    print STDERR $stats unless $opts{_quiet};
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

* Time each require.

* Stat: system/user time.

* Stat: number of open files (sockets).

* Stat: number of child processes.

* Stat: number of actual code lines (vs blanks, data, comment, POD)

* Stat: number of XS vs PP modules.

* Feature: remember last run's stats, compare with current run.

=cut

1;
