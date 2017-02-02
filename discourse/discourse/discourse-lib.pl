#!/usr/bin/perl

sub discourse {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab

        my $discourseemail = `discourse config:get DISCOURSE_DEVELOPER_EMAILS`;
        my $hostname = `hostname`;

        my $discourseemailform = <<END
    <div class="tab-pane active" id="discourse">
    <div>
        Here you can manage basic settings for your Discourse servers.
    </div>
    <small>Set email address(es) of admininistrator(s)):</small>
    <form class="passwordform" action="index.cgi?action=changediscourseemail&tab=discourse" method="post" onsubmit="emailSpinner();" accept-charset="utf-8" id="linform" autocomplete="off">
        <input id="discourseemail" type="password" name="discourseemail" autocomplete="off" value="$discourseemail">
        <button class="btn btn-default" type="submit" id="discourseemail_button">Set!</button>
    </form>
END
;
        my $hostnameform = <<END
    <small>Set the hostname Discourse should use:</small>
    <form class="passwordform" action="index.cgi?action=setdiscoursehostname&tab=security" method="post" onsubmit="hostnameSpinner();" accept-charset="utf-8" style="margin-bottom:26px;">
        <input id="discoursehostname" type="text" name="discoursehostname" autocomplete="off" value="$hostname">
        $curip
        <button class="btn btn-default" type="submit" id="hostname_button">Set!</button>
    </form>
    </div>
END
;
        return "$discourseemailform\n$hostnameform";

    } elsif ($action eq 'js') {
# Generate and return javascript the UI for this tab needs
        my $js = <<END
    \$(document).ready(function () {
    });

    function emailSpinner() {
        \$("#discourseemail_button").prop("disabled", true ).html('Set! <i class="fa fa-cog fa-spin"></i>');
    }
    function hostnameSpinner() {
        \$("#hostname_button").prop("disabled", true ).html('Set! <i class="fa fa-cog fa-spin"></i>');
    }

END
;
        return $js;

# This is called from the UI
    } elsif ($action eq 'setdiscourseemail' && defined $in{discourseemail}) {
        my $message;
        my $email = $in{discourseemail};
        if ($email) {
            my $cmd = qq[discourse config:set DISCOURSE_DEVELOPER_EMAILS=$email];
            $message .=  `$cmd`;
            # Also configure other servers in app
            my $rstatus = run_command($cmd, $internalip) if (defined &run_command);
            $message .= $rstatus unless ($rstatus =~ /OK:/);
            $message .=  "<div class=\"message\">The developer email was changed!</div>";
        }
        return $message;

    } elsif ($action eq 'setdiscoursehostname' && defined $in{discoursehostname}) {
        my $message;
        my $hostname = $in{discoursehostname};
        if ($hostname) {
            my $cmd = qq[discourse config:set DISCOURSE_HOSTNAME=$hostname];
            $message .=  `$cmd`;
            # Also configure other servers in app
            my $rstatus = run_command($cmd, $internalip) if (defined &run_command);
            $message .= $rstatus unless ($rstatus =~ /OK:/);
            $message .=  "<div class=\"message\">The Discourse hostname was changed!</div>";
        }
        return $message;

    }
}

1;
