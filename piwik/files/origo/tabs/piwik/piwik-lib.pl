#!/usr/bin/perl

use JSON;
use Digest::MD5 qw(md5 md5_hex md5_base64);

sub piwik {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
        my $form;
        # Redirect to upgrade page if still upgrading
        if (-e "/tmp/restoring") {
            $form .=  qq|<script>loc=document.location.href; setTimeout(function(){document.location=loc;}, 1500); </script>|;
        }
        $form .= <<END
    <div class="tab-pane" id="piwik">
        <div>
            Here you can manage basic security for Piwik.
        </div>
        <small>Set password for Piwik user "origo":</small>
        <form class="passwordform" action="index.cgi?action=changepiwikpassword&tab=piwik" method="post" onsubmit="passwordSpinner();" accept-charset="utf-8" id="piwikform" autocomplete="off">
            <input type="password" name="piwikpassword" autocomplete="off" value="" class="password" onfocus="doStrength(this);">
            <button class="btn btn-default" type="submit">Set!</button>
        </form>
        <small style="margin-top:10px;">
            After setting the password <a target="_blank" href="https://$externalip.$appinfo{dnsdomain}/piwik">log in here</a> with username "origo" and your password.
        </small>
    </div>
END
        ;

        return $form;

    } elsif ($action eq 'js') {
        # Generate and return javascript the UI for this tab needs
        my $js = <<END
        \$("#currentwpadmin").attr("href", "https://$externalip.$appinfo{dnsdomain}/piwik");
        \$("#currentwpadmin").text("to Piwik");
        \$("#currentwpadmin").parent().show()
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

    } elsif ($action eq 'changepiwikpassword' && defined $in{piwikpassword}) {
        my $message;
        my $pwd = $in{piwikpassword};
        if ($pwd) {
#            my $password = md5_base64($pwd);
            my $password = `php -r 'echo password_hash(md5("$pwd"), PASSWORD_DEFAULT);'`;
            $message .= `mysql piwik -e 'UPDATE piwik_user SET password = "$password" WHERE login = "origo" AND superuser_access = 1;'`;
            $message .= "<div class=\"message\">The Piwik password was changed!</div>";
        }
        return $message;
    }
}


1;