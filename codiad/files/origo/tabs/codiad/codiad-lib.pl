#!/usr/bin/perl

use JSON;

sub codiad {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab

    # First let's make sure install.php has been patched - WP may have been upgraded
        unless (`grep "HTTP_HOST" /usr/share/wordpress/wp-admin/install.php`) {
            ;
        } else {
            ;# "Already patched\n";
        }

        my $form;

        return $form;

    } elsif ($action eq 'js') {
# Generate and return javascript the UI for this tab needs
        my $js = <<END
        \$('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
        })
END
;
        return $js;


# This is called from index.cgi (the UI)
    } elsif ($action eq 'upgrade') {
        my $res;
        return $res;

# This is called from origo-ubuntu.pl when rebooting and with status "upgrading"
    } elsif ($action eq 'restore') {
        my $res;
        return $res;

    }
}


1;
