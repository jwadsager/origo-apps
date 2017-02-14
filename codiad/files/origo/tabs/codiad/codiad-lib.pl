#!/usr/bin/perl

use JSON;

sub codiad {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab

    # First let's make sure Apache is patched to handle perl scripts
        if (-s "/var/www/html/config.php") {
            ;
        } else {
            ;# "Already patched\n";
        }

        my $form;


        # Redirect to upgrade page if still upgrading
        if (-e "/tmp/restoring") {
            $form .=  qq|<script>loc=document.location.href; setTimeout(function(){document.location=loc;}, 1500); </script>|;
        # Redirect to Codiad install page if not configured
        } elsif (-z "/var/www/html/config.php") {
            $form .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/"; </script>|;
        }

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
