#!/usr/bin/perl

use JSON;

sub codiad {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
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


        $form .= <<END
    <div class="tab-pane active" id="codiad">
    <div>
        Here you can manage basic security settings for your development server.
    </div>
    <small>Set password for Codiad user "origo":</small>
    <form class="passwordform" action="index.cgi?action=changelinuxpassword&tab=security" method="post" onsubmit="passwordSpinner();" accept-charset="utf-8" id="linform" autocomplete="off">
        <input id="codiadpassword" type="password" name="codiadpassword" autocomplete="off" value="" class="password" onfocus="doStrength(this);">
        <button class="btn btn-default" type="submit" id="password_button">Set!</button>
    </form>
    </div>
END
        ;

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
