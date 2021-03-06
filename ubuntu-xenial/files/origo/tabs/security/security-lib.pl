#!/usr/bin/perl

sub security {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab

        my $allow = `cat /etc/hosts.allow`;
        my $limitssh;
        $limitssh = $1 if ($allow =~ /sshd: ?(.*) #origo/);

        my $pwform = <<END
    <div class="tab-pane active" id="security">
    <div>
        Here you can manage basic security settings for the servers in your app.
    </div>
    <small>Set password for Linux user "origo":</small>
    <form class="passwordform" action="index.cgi?action=changelinuxpassword&tab=security" method="post" onsubmit="passwordSpinner();" accept-charset="utf-8" id="linform" autocomplete="off">
        <input id="linuxpassword" type="password" name="linuxpassword" autocomplete="off" value="" class="password" onfocus="doStrength(this);">
        <button class="btn btn-default" type="submit" id="password_button">Set!</button>
    </form>
END
;

        my $curip;
        $curip = qq|<span style="float: left; font-size: 13px;">leave empty to disallow all access, your current IP is <a style="text-decoration: none;" href="#" onclick="\$('#limitssh').val('$ENV{HTTP_X_FORWARDED_FOR} ' + \$('#limitssh').val());">$ENV{HTTP_X_FORWARDED_FOR}</a></span>| if ($ENV{HTTP_X_FORWARDED_FOR});

        my $curipwp;
        $curipwp = qq|<span style="float: left; font-size: 13px;">leave empty to allow login from anywhere, your current IP is <a href="#" onclick="\$('#wplimit').val('$ENV{HTTP_X_FORWARDED_FOR} ' + \$('#wplimit').val());">$ENV{HTTP_X_FORWARDED_FOR}</a></span>| if ($ENV{HTTP_X_FORWARDED_FOR});

        my $limitform = <<END
    <small>Allow ssh and webmin login from:</small>
    <form class="passwordform" action="index.cgi?action=limitssh&tab=security" method="post" onsubmit="limitSpinner();" accept-charset="utf-8" style="margin-bottom:26px;">
        <input id="limitssh" type="text" name="limitssh" value="$limitssh" placeholder="IP address or network, e.g. '192.168.0.0/24 127.0.0.1'">
        $curip
        <button class="btn btn-default" type="submit" id="limit_button">Set!</button>
    </form>
    </div>
END
;
        return "$pwform\n$limitform";

    } elsif ($action eq 'js') {
# Generate and return javascript the UI for this tab needs
        my $js = <<END
    \$(document).ready(function () {
        \$('#linuxpassword').strength({
            strengthClass: 'strength',
            strengthMeterClass: 'strength_meter',
            strengthButtonClass: 'button_strength',
            strengthButtonText: 'Show Password',
            strengthButtonTextToggle: 'Hide Password'
        });
        \$('#linuxpassword').val('');
    });

    function doStrength(item) {
        return true;
        console.log("Strengthening", '#'+ item.id);
        \$('#'+ item.id).strength({
            strengthClass: 'strength',
            strengthMeterClass: 'strength_meter',
            strengthButtonClass: 'button_strength',
            strengthButtonText: 'Show Password',
            strengthButtonTextToggle: 'Hide Password',
            id: item.id
        });
    };

    function passwordSpinner() {
        \$("#password_button").prop("disabled", true ).html('Set! <i class="fa fa-cog fa-spin"></i>');
    }
    function limitSpinner() {
        \$("#limit_button").prop("disabled", true ).html('Set! <i class="fa fa-cog fa-spin"></i>');
    }

END
;
        return $js;

# This is called from the UI
    } elsif ($action eq 'upgrade') {
        my $res;
        my $json_text = `curl -ks "https://10.0.0.1/steamengine/servers/this"`;
        my $rdom = from_json($json_text);
        my $uuid = $rdom->{uuid};
        my $dumploc;
        my %activepools = mountPools();
        foreach my $pool (values %activepools) {
            my $sid = "pool" . $pool->{id};
            if ($mounts =~ /\mnt\/fuel\/$sid/) { # pool mounted
                $dumploc = "/mnt/fuel/$sid/upgradedata/$uuid";
                `mkdir -p $dumploc`;
                last;
            }
        }
        if (-d $dumploc) {
            # Dump limit
            my $limit = get_limit();
            `echo "$limit" > $dumploc/security.limit`;
            if (-e "$dumploc/security.limit") {
                $res = "OK: Security data dumped successfully to $dumploc";
            } else {
                $res = "There was a problem dumping security data to $dumploc!";
            }
        } else {
            $res = "There was a problem dumping limit $limit to $dumploc!";
        }
        return $res;

# This is called from origo-ubuntu.pl when rebooting and with status "upgrading"
    } elsif ($action eq 'restore') {
        my $srcloc = $in{sourcedir};
        my $res;
        if (-e "$srcloc/security.limit") {
            my $limit;
            $limit = `cat $srcloc/security.limit`;
            chomp $limit;
            $res = "OK: ";
            $res .= set_limit($limit);
        }
        $res = "Unable to restore security settings from $srcloc/security.limit!" unless ($res);
        return $res;

    } elsif ($action eq 'changelinuxpassword' && defined $in{linuxpassword}) {
        my $message;
        my $pwd = $in{linuxpassword};
        if ($pwd) {
            my $cmd = qq[echo "origo:$pwd" | chpasswd];
            $message .=  `$cmd`;
            # Also configure other servers in app
            my $rstatus = run_command($cmd, $internalip) if (defined &run_command);
            $message .= $rstatus unless ($rstatus =~ /OK:/);
            # Also allow Webmin to execute calls on remote servers
            `perl -pi -e 's/pass=.*/pass=$in{linuxpassword}/' /etc/webmin/servers/*.serv`;
            $message .=  "<div class=\"message\">The Linux password was changed!</div>";
        }
        return $message;

    } elsif ($action eq 'limitssh' && defined $in{limitssh}) {
        my $limit = $in{limitssh};
        return set_limit($limit);

    }
}

## Validates a string of ipv4 addresses and networks
sub validate_limit {
    my $limit = shift;
    my $mess;
    my @limits = split(/ +/, $limit);
    my @validlimits;
    foreach my $lim (@limits) {
        # Check if valid ipv4 address or network
        my $ip = $lim;
        my $net;
        if ($lim =~ /(\S+)\/(\S+)/) {
            $ip = $1;
            $net = $2;
            $lim = "$1\\/$2";
            $ip = '' unless ($net =~ /^\d\d?$/);
        }
        if (!(defined &check_ipaddress) || check_ipaddress($ip)) {
            push @validlimits, $lim;
        } else {
            $mess .=  "<div class=\"message\">Invalid IP address or network!</div>";
        }
    };
    my $validlimit = join(' ', @validlimits);
    return ($validlimit, $mess);
}

sub get_limit {
    my $limit;
    my $conf = "/etc/apache2/sites-available/webmin-ssl";
    # Handle name change in Xenial
    $conf .= '.conf' if (-e "$conf.conf");

    open FILE, "<$conf";
    my @lines = <FILE>;
    for (@lines) {
        if ($_ =~ /allow from (.*) \#origo/) {
            $limit = $1;
            last;
        }
    }
    close(FILE);
    return $limit;
}

sub set_limit {
    my $limit = shift;
    my $message;
    my ($validlimit, $mess) = validate_limit($limit);
    $message .= $mess;
    my $iip = "$1.0" if ($internalip =~ /(\d+\.\d+\.\d+)\.\d+/);
    my $cmd;
    # Configure webmin on admin server
    $cmd = qq|perl -pi -e "s/allow=(.*)/allow=$iip\\/24 127.0.0.1 $validlimit/;" /etc/webmin/miniserv.conf|;
    $message .= `$cmd`;
    my $conf = "/etc/apache2/sites-available/webmin-ssl";
    # Handle name change in Xenial
    $conf .= '.conf' if (-e "$conf.conf");
    $cmd = qq|perl -pi -e 's/allow from (.*) \#origo/allow from $validlimit #origo/;' $conf|;
    $message .= `$cmd`;
    # Configure ssh on admin server
    $cmd = qq|perl -pi -e 's/sshd: ?(.*) \#origo/sshd: $validlimit #origo/;' /etc/hosts.allow|;
    $message .= `$cmd`;
    # Also configure ssh on other servers in app
    my $rstatus = run_command($cmd, $internalip) if (defined &run_command);
    $message .= $rstatus unless ($rstatus =~ /OK:/);
    # Verify a bit
    my $allow = `cat /etc/hosts.allow`;
    if ($allow=~ /sshd: ?(.*) #origo/)
    {
        $limitssh = $1;
        if ($limitssh) {
            $message .=  "<div class=\"message\">SSH and Webmin can be accessed from $limitssh!</div>";
        } else {
            $message .=  "<div class=\"message\">SSH and Webmin access removed!</div>";
        }
    } else {
        $message .=  "<div class=\"message\">SSH has been manually configured - trying to reconfigure</div>";
        $validlimit =~ s/\\//g;
        `echo "allow=$iip/24 127.0.0.1 $validlimit" >> /etc/webmin/miniserv.conf` unless (`grep "allow=" /etc/webmin/miniserv.conf`);
        `echo "sshd: ALL" >> /etc/hosts.deny` unless (`grep "sshd: ALL" /etc/hosts.deny`);
        `echo "sshd: $validlimit #origo" >> /etc/hosts.allow` unless (`grep "sshd: .*origo" /etc/hosts.allow`);
        $limitssh = $1 if (`cat /etc/hosts.allow` =~ /sshd: ?(.*) #origo/);
    }
    # Reload Webmin
    if (defined (&reload_miniserv)) {
        reload_miniserv();
    } else {
        `service webmin restart`;
    }
    # Reload apache
    $cmd = qq|service apache2 reload|;
    `$cmd`;
    # Also reload on other servers
    run_command($cmd, $internalip) if (defined &run_command);
    chomp $message;
    return $message;
}

1;
