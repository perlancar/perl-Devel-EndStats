package Devel::EndStats;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);

# VERSION

my %excluded;

our %opts = (
    verbose      => 0,
    sort         => 'time',
    _quiet       => 0,
);

# not yet
sub _inc_handler {
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

my $start_time;
my %inc_info;
my $order;
my $req_level = -1;
my @req_times;
sub import {
    my ($class, %args) = @_;
    $opts{verbose} = $ENV{VERBOSE} if defined($ENV{VERBOSE});
    if ($ENV{DEVELENDSTATS_OPTS}) {
        while ($ENV{DEVELENDSTATS_OPTS} =~ /(\w+)=(\S+)/g) {
            $opts{$1} = $2;
        }
    }
    $opts{$_} = $args{$_} for keys %args;
    #unshift @INC, \&_inc_handler;
    *CORE::GLOBAL::require = sub {
        my ($arg) = @_;
        $req_level++;

        $inc_info{$arg}         ||= {
            order  => ++$order,
            caller => (caller(0))[0],
            time   => 0,
        };

        my $st = [gettimeofday];
        my $res;
        if (wantarray) { $res = [CORE::require $arg] } else { $res = CORE::require $arg }
        my $iv = tv_interval($st);

        # still can't make exclusive time work
        #$req_times[$req_level] += $iv;
        #my $iv_inner = 0;
        #for ($req_level+1 .. @req_times-1) { $iv_inner += $req_times[$_] }
        #$inc_info{$arg}{time} += $req_times[$req_level] - $iv_inner;
        #splice @req_times, $req_level+1;
        #$req_times[$req_level] = 0;

        # inclusive time
        $inc_info{$arg}{time} = $iv;

        $req_level--;
        if (wantarray) { return @$res } else { return $res }
    };

    $start_time = [gettimeofday];
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

            # ?
            "subs.pm",
            "overload.pm",
        ) {
            $excluded{$_}++;
        }
        $begin_success++;
    }
}

our $stats;
END {
    my $secs = $start_time ? tv_interval($start_time) : (time()-$^T);

    $stats  = "\n";
    $stats .= "# BEGIN stats from Devel::EndStats\n";

    if ($begin_success) {

        $stats .= sprintf "# Program runtime duration: %.6fs\n", $secs;

        my $files = 0;
        my $lines = 0;
        local *F;
        for my $r (keys %INC) {
            next if $excluded{$r};
            $files++;
            next unless $INC{$r}; # undefined in some cases
            open F, $INC{$r} or do {
                warn "Devel::EndStats: Can't open $INC{$r}, skipped\n";
                next;
            };
            my $flines = 0;
            while (<F>) { $lines++; $flines++ }
            $inc_info{$r}{lines} = $flines;
        }
        $stats .= sprintf "# Total number of required files loaded: %d\n",
            $files;
        $stats .= sprintf "# Total number of required lines loaded: %d\n",
            $lines;

        if ($opts{verbose}) {
            my $s = $opts{sort};
            my $sortsub;
            if ($s eq 'lines') {
                $sortsub = sub {$inc_info{$b}{$s} <=> $inc_info{$a}{$s}};
            } elsif ($s eq 'time') {
                $sortsub = sub {$inc_info{$b}{$s} <=> $inc_info{$a}{$s}};
            } elsif ($s eq 'order') {
                $sortsub = sub {($inc_info{$a}{$s}||0) <=> ($inc_info{$b}{$s}||0)};
            } else {
                $s = 'caller';
                $sortsub = sub {$inc_info{$a}{$s} cmp $inc_info{$b}{$s}};
            }
            for my $r (sort $sortsub keys %inc_info) {
                next unless $inc_info{$r}{lines};
                $inc_info{$r}{time} ||= 0;
                $stats .= sprintf "#   #%3d  %5d lines  %.6fs(%3d%%)  %s (loaded by %s)\n",
                     $inc_info{$r}{order}, $inc_info{$r}{lines}, $inc_info{$r}{time}, $secs ? $inc_info{$r}{time}/$secs*100 : 0,
                         $r, $inc_info{$r}{caller};
            }
        }

    } else {

        $stats .= "# BEGIN phase didn't succeed?\n";

    }

    $stats .= "# END stats\n";
    print STDERR $stats unless $opts{_quiet};
}

1;
# ABSTRACT: Show various statistics at the end of program run

=head1 SYNOPSIS

 # from the command line
 % perl -MDevel::EndStats script.pl

 ##### sample output #####
 <normal script output, if any...>

 # BEGIN stats from Devel::EndStats
 # Program runtime duration: 0.055s
 # Total number of required files loaded: 132
 # Total number of required lines loaded: 48772
 # END stats

 ##### sample output (with verbose=1, some cut) #####
 <normal script output, if any...>

 # BEGIN stats from Devel::EndStats
 # Program runtime duration: 0.055s
 # Total number of required files loaded: 132
 # Total number of required lines loaded: 48772
 #   #  1   1747 lines  0.023489s( 43%)  Log/Any/App.pm (loaded by main)
 #   # 52   1106 lines  0.015112s( 28%)  Log/Log4perl/Logger.pm (loaded by Log::Log4perl)
 #   # 17    190 lines  0.011983s( 22%)  Log/Any/Adapter.pm (loaded by Log::Any::App)
 #   # 18    152 lines  0.011679s( 21%)  Log/Any/Manager.pm (loaded by Log::Any::Adapter)
 #   #  5    981 lines  0.007299s( 13%)  File/Path.pm (loaded by Log::Any::App)
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

=item * sort => STR (default 'time')

Set how to sort the list of loaded modules ('time' = by load time, 'caller' = by
first caller's package, 'order' = by order of loading, 'lines' = by number of
lines). Only relevant when 'verbose' is on.

=back


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

* Exclusive instead of inclusive timing for each require.

* Stat: memory usage.

* Stat: system/user time.

* Stat: number of open files (sockets).

* Stat: number of child processes.

* Stat: number of actual code lines (vs blanks, data, comment, POD)

* Stat: number of XS vs PP modules.

* Feature: remember last run's stats, compare with current run.

=cut

1;
