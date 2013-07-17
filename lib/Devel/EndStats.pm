package Devel::EndStats;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);

# VERSION

# exclude modules which we use ourselves
my %excluded = map {$_=>1} (
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
);

our %opts = (
    verbose      => 0,
    sort         => 'lines',
    _quiet       => 0,
    force        => 0,
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

    my @loaded = grep {!$excluded{$_}} keys(%INC);
    warn join(
        "",
        "There are already a bunch of modules loaded",
        (" (".join(", ", @loaded).")") x !!$opts{verbose},
        " before Devel::EndStats has a chance to install its require hook. ",
        "For better results, it is recommended that you load ",
        __PACKAGE__, " before others.\n",
    ) if @loaded > 5;

    #unshift @INC, \&_inc_handler;
    *CORE::GLOBAL::require = sub {
        my ($arg) = @_;
        return 0 if $INC{$arg};

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
        $begin_success++;
    }
}

our $stats;
END {
    my $secs = $start_time ? tv_interval($start_time) : (time()-$^T);

    $stats = "";

    if ($begin_success || $opts{force}) {

        $stats .= "\n";
        $stats .= "# Start stats from Devel::EndStats:\n";
        $stats .= sprintf "# Program runtime duration: %.3fs\n", $secs;

        my $files = 0;
        my $lines = 0;
        local *F;
        for my $r (keys %INC) {
            next if $excluded{$r};
            $files++;
            next unless $INC{$r}; # skip modules that failed to be require()-ed
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
            my $reverse;
            if ($s =~ /^(-?)l(?:ines)?/) {
                $reverse = $1;
                $sortsub = sub {($inc_info{$b}{$s}||0) <=> ($inc_info{$a}{$s}||0)};
            } elsif ($s =~ /^(-)t(?:ime)?/) {
                $reverse = $1;
                $sortsub = sub {$inc_info{$b}{$s} <=> $inc_info{$a}{$s}};
            } elsif ($s =~ /^(-?)o(?:rder)?/) {
                $reverse = $1;
                $sortsub = sub {($inc_info{$a}{$s}||0) <=> ($inc_info{$b}{$s}||0)};
            } elsif ($s =~ /^(-?)f(?:ile)?/) {
                $reverse = $1;
                $sortsub = sub {$a cmp $b};
            } else {
                # sort by caller;
                $reverse = $s =~ /-/;
                $sortsub = sub {$inc_info{$a}{$s} cmp $inc_info{$b}{$s}};
            }
            my @rr = sort $sortsub keys %inc_info;
            @rr = reverse @rr if $reverse;
            for my $r (@rr) {
                next unless $inc_info{$r}{lines};
                $inc_info{$r}{time} ||= 0;
                $stats .= sprintf "#   #%3s  %5d lines  %7.3fms(%3d%%)  %s (loaded by %s)\n",
                     $inc_info{$r}{order} || '?', $inc_info{$r}{lines}, $inc_info{$r}{time}*1000, $secs ? $inc_info{$r}{time}/$secs*100 : 0,
                         $r, ($inc_info{$r}{caller} || "?");
            }
        }

        $stats .= "# End of stats\n";

    }

    print STDERR $stats unless $opts{_quiet};
}

1;
# ABSTRACT: Display run time and dependencies after running code

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

Devel::EndStats should be loaded before other modules,
for example by running it on the command-line,
as shown in the SYNOPSIS.


=head1 OPTIONS

Some options are accepted. They can be passed via the B<use> statement:

 # from the command line
 % perl -MDevel::EndStats=verbose,1 script.pl

 # from script
 use Devel::EndStats verbose=>1;

or via the DEVELENDSTATS_OPTS environment variable:

 % DEVELENDSTATS_OPTS='verbose=1' perl -MDevel::EndStats script.pl

=over 4

=item * verbose => BOOL (default: 0)

Can also be set via VERBOSE environment variable. If set to true, display more
statistics (like per-module statistics).

=item * sort => STR (default: 'time')

Set how to sort the list of loaded modules ('file' = by file, 'time' = by load
time, 'caller' = by first caller's package, 'order' = by order of loading,
'lines' = by number of lines). Only relevant when 'verbose' is on.

=item * force => BOOL (default: 0)

By default, if BEGIN phase did not succeed, stats will not be shown. This option
forces displaying the stats.

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

There are many modules on CPAN that can be used to generate dependency
information for your code. Neil Bowers has written a
L<review|http://neilb.org/reviews/dependencies.html> that covers most of them.

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
