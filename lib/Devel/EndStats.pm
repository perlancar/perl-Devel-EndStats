package Devel::EndStats;
# ABSTRACT: Show various statistics at the end of program run

=head1 SYNOPSIS

    perl -MDevel::EndStats script.pl

=head1 DESCRIPTION

Devel::EndStats runs in the END block, displaying various statistics about your
program, such as: how many seconds the program ran, how many module files and
total number of lines loaded (by inspecting %INC), etc.

Some notes/caveats:

END blocks declared after Devel::EndStats' will be executed after it, so in that
case it's ideal to load Devel::EndStats as the last module.

In total number of modules loaded, Devel::EndStats itself is excluded.

=cut

# deliberately not using warnings, strict, or other modules

END {
    print "# BEGIN stats from Devel::EndStats\n";

    printf "# Program runtime duration (s): %d\n", (time() - $^T);

    #use Data::Dump; dd %INC;
    printf "# Total number of module files loaded: %d\n", scalar(keys %INC)-1;

    my $lines = 0;
    local *F;
    for (keys %INC) {
        next if m!^(Devel/EndStats)\.pm$!;
        open F, $INC{$_} or next;
        $lines++ while <F>;
    }
    printf "# Total number of modules lines loaded: %d\n", $lines;

    print "# END stats\n";
}

=head1 FAQ

=head2 What is the purpose of this module?

This module might be useful during development. I first wrote this module when
trying to reduce startup overhead of a command-line application, by looking at
how many modules the app has loaded and try to avoid loading modules whenever
it's unnecessary.

=head2 Can you add (so and so) information to the stats?

Sure, if it's useful. As they say, (comments|patches) are welcome.

=head1 SEE ALSO

=cut

1;
