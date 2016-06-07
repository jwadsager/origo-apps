#!/usr/bin/perl

use JSON;

my $drupalroot = '/var/www/html';
my $configdir = "$drupalroot/sites";


# Return an array of all Drupal sites, aliases included
sub getDrupalSites {
    my @sites;
    opendir(DIR, $configdir) or die $!;
    while (my $file = readdir(DIR)) {
        next if $file =~ /^[.]/;
        next unless (-d "$configdir/$file") or (-l "$configdir/$file");
        next if $file eq 'all';
        push (@sites, $file);
    }
    closedir(DIR);

    return @sites;
}

# Return html for a single site configuration
sub getLoopTab {
    my $domain = shift;
    my $domain_without_origo = shift;
    my $domain_aliases = shift;
    $site_aliases = join(' ', split(' ', $domain_aliases));

    my $loop_user;
    if ($domain eq 'new') {
        $loop_user = 'admin';
    } elsif ($domain eq 'loopsecurity') {
        my $allow = `cat /etc/hosts.allow`;
        my $loop_limit = $1 if ($allow =~ /allow from (.+) \#origo/);
        my $current_ip = qq|<span style="float: left; font-size: 13px;">Leave empty to allow login from anywhere, your current IP is <a href="#" onclick="\$('#loop-limit').val('$ENV{HTTP_X_FORWARDED_FOR} ' + \$('#loop-limit').val());">$ENV{HTTP_X_FORWARDED_FOR}</a></span>| if ($ENV{HTTP_X_FORWARDED_FOR});

        my $loopsecurityform = <<END
<div class="tab-pane" id="loop-security">
    <form class="passwordform" action="index.cgi?action=looplimit\&tab=os2loop\&show=loop-security" method="post" accept-charset="utf-8" style="margin-bottom:36px;" autocomplete="off">
        <small>Limit login for all sites to:</small>
        <input id="loop-limit" type="text" name="loop-limit" value="$loop_limit" placeholder="IP address or network, e.g. '192.168.0.0/24 127.0.0.1'">
        $current_ip
        <button class="btn btn-default" type="submit" onclick="spinner(this);">Set!</button>
    </form>
</div>
END
;
        return $loopsecurityform;
    } else {
        my $db = "os2loop_$domain_without_origo";
        $loop_user = `echo "select name from users where uid=1;" | mysql -s $db`;
        chomp $loop_user;
        $loop_user = $domain unless ($loop_user);
    }

    my $resetbutton = qq|<button class="btn btn-danger" rel="tooltip" data-placement="top" title="This will remove your website and wipe your database. Are you sure this is what you want to do?" onclick="confirmWPAction('loopremove', '$domain_without_origo');" type="button">Remove website</button>|;
    my $manageform = <<END
    <div class="tab-pane" id="$domain_without_origo-site">
    <form class="passwordform wpform" id="wpform_$domain_without_origo" action="index.cgi?tab=os2loop\&show=$domain_without_origo-site" method="post" accept-charset="utf-8" autocomplete="off">
        <div>
            <small>The website's domain name:</small>
            <input class="loopdomain" id="loopdomain_$domain_without_origo" type="text" name="loopdomain_$domain_without_origo" value="$domain" disabled autocomplete="off">
        </div>
        <div>
            <small>Aliases for the website:</small>
            <input class="wpalias" id="wpaliases_$domain_without_origo" type="text" name="wpaliases_$domain_without_origo" value="$domain_aliases" autocomplete="off" />
            <input type="hidden" id="wpaliases_h_$domain_without_origo" name="wpaliases_h_$domain_without_origo" value="$domain_aliases" autocomplete="off" />
            <button type="submit" class="btn btn-default" onclick="spinner(this); \$('#action_$domain_without_origo').val('domain_aliases'); submit();" rel="tooltip" data-placement="top" title="Aliases that are not FQDNs will be created in the origo.io domain as [alias].origo.io">Set!</button>
        </div>
        <div>
            <small>Set password for OS2Loop user '$loop_user':</small>
            <input id="wppassword_$domain_without_origo" type="password" name="wppassword" autocomplete="off" value="" class="password">
            <button type="submit" class="btn btn-default" onclick="spinner(this); \$('#action_$domain_without_origo').val('wppassword'); submit();">Set!</button>
        </div>
    <div style="height:10px;"></div>
END
;

    if ($domain eq 'new') {
        $resetbutton = qq|<button class="btn btn-info" type="button" rel="tooltip" data-placement="top" title="Click to create your new website!" onclick="if (\$('#loopdomain_new').val()) {spinner(this); \$('#action_$domain_without_origo').val('loopcreate'); \$('#wpform_$domain_without_origo').submit();} else {\$('#loopdomain_new').css('border','1px solid #f39c12'); \$('#loopdomain_new').focus(); return false;}">Create website</button>|;

        $manageform = <<END
    <div class="tab-pane" id="$domain-site">
    <form class="passwordform wpform" id="wpform_$domain_without_origo" action="index.cgi?tab=os2loop\&show=$domain_without_origo-site" method="post" accept-charset="utf-8" autocomplete="off">
        <div>
            <small>The website's domain name:</small>
            <input class="loopdomain required" id="loopdomain_$domain_without_origo" type="text" name="loopdomain_$domain_without_origo" value="" autocomplete="off">
        </div>
        <div>
            <small>Aliases for the website:</small>
            <input class="loopdomain" id="wpaliases_$domain_without_origo" type="text" name="wpaliases_$domain_without_origo" value="$domain_aliases" autocomplete="off">
        </div>
        <div>
            <small>Set password for OS2Loop user 'admin':</small>
            <input id="wppassword_$domain_without_origo" type="password" name="wppassword" autocomplete="off" value="" disabled class="disabled" placeholder="Password can be set after creating website">
            <button class="btn btn-default disabled" disabled>Set!</button>
        </div>
    <div style="height:10px;"></div>
END
;
    }

    my $backupform .= <<END
    <div class="mbl">
        $resetbutton
        <input type="hidden" name="action" id="action_$domain_without_origo">
        <input type="hidden" name="wp" id="wp_$domain_without_origo" value="$domain">
    </div>
    </form>
    </div>
END
;

    return <<END
$manageform
$backupform
END
;
}

# Return html for dropdown
sub getLoopDropdown {
    my $websitedrops;
    my @sites = getDrupalSites();

    foreach my $file (@sites) {
        next if (-l "$configdir/$file");
        next if $file eq 'default';
        my $domain = $file;
        my $domain_without_origo = $domain;
        $domain_without_origo = $1 if ($domain_without_origo =~ /(.+)\.origo\.io/);
        $domain_without_origo =~ tr/\./_/;
        $websitedrops .= <<END
<li><a href="#$domain_without_origo-site" tabindex="-1" data-toggle="tab" id="$domain">$domain</a></li>
END
;
    }

    my $dropdown = <<END
<li class="dropdown">
    <a href="#" id="myTabDrop1" class="dropdown-toggle" data-toggle="dropdown">os2loop <b class="caret"></b></a>
    <span class="dropdown-arrow"></span>
    <ul class="dropdown-menu" role="menu" aria-labelledby="myTabDrop1">
        <li><a href="#default-site" tabindex="-1" data-toggle="tab">Default website</a></li>
        $websitedrops
        <li><a href="#new-site" tabindex="-1" data-toggle="tab">Add new website...</a></li>
        <!--<li><a href="#loop-security" tabindex="-1" data-toggle="tab">Security</a></li>-->
    </ul>
</li>
END
;
    return $dropdown;
}

# Called from index.cgi
sub os2loop {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    # Generate and return the html form for this tab
    if ($action eq 'form') {
        my $form;
        my %aliases;
        my @sites = getDrupalSites();

        foreach my $file (@sites) {
            if (-l "$configdir/$file") {
                my $link = readlink("$configdir/$file");
                $aliases{$link} .= "$file ";
            }
        }

        foreach my $file (@sites) {
            next if (-l "$configdir/$file");
            my $domain = $file;
            my $domain_without_origo = $domain;
            $domain_without_origo = $1 if ($domain_without_origo =~ /(.+)\.origo\.io/);
            $domain_without_origo =~ tr/\./_/;
            $form .= getLoopTab($domain, $domain_without_origo, $aliases{$file});
        }

        $form .=  getLoopTab('new', 'new');
        $form .=  getLoopTab('loopsecurity', 'loopsecurity');

        # Redirect to upgrade page if still upgrading
        if (-e "/tmp/restoring") {
            $form .=  qq|<script>loc=document.location.href; setTimeout(function(){document.location=loc;}, 1500); </script>|;
        # Redirect to install page if default site not configured
        } elsif (!(`echo "SHOW TABLES LIKE 'users'" | mysql os2loop_default`)) {
            $form .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/install.php?profile=loopdk&locale=en"; </script>|;
        }

        return $form;

    # Generate and return javascript for this tab
    } elsif ($action eq 'js') {
        my $js = <<END
        \$('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            var site = e.target.id;
            var href = e.target.href;
            var regexp = /#(.+)-site/;
            var match = regexp.exec(href);
            if (href.indexOf('#new')!=-1) { // set standard grey border in case it has failed validation previously
                \$('#loopdomain_new').css('border','1px solid #CCCCCC'); \$('#loopdomain_new').focus();
            }
            \$("#currentwpadmin").parent().show();
            if (!match || match[1] == 'default' || match[1] == 'new') {
                \$("#currentwp").attr("href", "http://$externalip/");
                \$("#currentwp").text("to default website");
            } else {
                var siteaddr = site;
                if (site.indexOf(".")==-1) siteaddr = site + ".origo.io"
                \$("#currentwp").attr("href", "http://" + siteaddr + "/");
                \$("#currentwp").text("to " + site + " website");
            }
            if (match) {
                setTimeout(
                    function() {
                        if (\$("#wpaliases_h_" + match[1]).val() == '')
                            \$("#wpaliases_" + match[1]).val("");
                        \$("#wppassword_" + match[1]).val("--");
                        \$("#wppassword_" + match[1]).val("");
                    }, 100
                )
            }
        })

        \$(".loopdomain").keypress(function(event){
            var inputValue = event.which;
            //if digits or not a space then don't let keypress work.
            if(
                (inputValue > 47 && inputValue < 58) //numbers
                || (inputValue > 64 && inputValue < 90) //letters
                || (inputValue > 96 && inputValue < 122)
                || inputValue==46 //period
                || inputValue==45 //dash
                || inputValue==95 //underscore
                || inputValue==8 //backspace
                || inputValue==127 //del
                || inputValue==9 //tab
                || inputValue==0 //tab?
            ) {
                ; // allow keypress
            } else
            {
                event.preventDefault();
            }
        });

        \$(".wpalias").keypress(function(event){
            var inputValue = event.which;
            // if digits or not a space then don't let keypress work.
            if(
                (inputValue > 47 && inputValue < 58) //numbers
                || (inputValue > 64 && inputValue < 90) //letters
                || (inputValue > 96 && inputValue < 122)
                || inputValue==46 //period
                || inputValue==45 //dash
                || inputValue==95 //underscore
                || inputValue==8 //backspace
                || inputValue==127 //del
                || inputValue==32 //space
                || inputValue==9 //tab
                || inputValue==0 //tab?
            ) {
                ; // allow keypress
            } else
            {
                event.preventDefault();
            }
        });

        function confirmWPAction(action, wpname) {
            if (action == 'loopremove') {
                \$('#action_' + wpname).val(action);
                \$('#confirmdialog').prop('actionform', '#wpform_' + wpname);
                \$('#confirmdialog').modal({'backdrop': false, 'show': true});
                return false;
            }
        };

END
;
        return $js;


    } elsif ($action eq 'tab') {
        return getLoopDropdown();

    } elsif ($action eq 'upgrade') {
        my $res;
        my $srcloc = $configdir;
        my $dumploc = $in{targetdir};

        if (-d $dumploc) {
            # Dump database
            `mysqldump --databases \$(mysql -N information_schema -e "SELECT DISTINCT(TABLE_SCHEMA) FROM tables WHERE TABLE_SCHEMA LIKE 'os2loop_%'") > $dumploc/os2loop.sql`;
            # Copy wp-content (remove target first, in order to be able to compare sizes)
            `rm -r $dumploc/sites`;
            `cp -r $srcloc $dumploc`;
        }

        my $srcsize = `du -bs $srcloc`;
        $srcsize = $1 if ($srcsize =~ /(\d+)/);
        my $dumpsize = `du -bs $dumploc/sites`;
        $dumpsize = $1 if ($dumpsize =~ /(\d+)/);
        if ($srcsize == $dumpsize) {
            $res = "OK: Configuration and database dumped successfully to $dumploc";
        } else {
            $res = "There was a problem dumping data to $dumploc ($srcsize <> $dumpsize)!";
        }
        return $res;

    # Called from origo-ubuntu.pl when rebooting and with status "upgrading"
    } elsif ($action eq 'restore') {
        my $srcloc = $in{sourcedir};
        my $res;
        my $dumploc  = $configdir;
        if (-d $srcloc && -d $dumploc) {
            $res = "OK: ";

            $srcdir = "sites/*";
            $dumploc  = $configdir;
            $res .= qq|copying $srcloc/$srcdir -> $dumploc, |;
            $res .= `cp --backup -a $srcloc/$srcdir "$dumploc"`;
            $res .= `chown -R www-data:www-data $dumploc`;

            if (-e "$srcloc/os2loop.sql") {
                $res .= qq|restoring db, |;
                $res .= `/usr/bin/mysql < $srcloc/os2loop.sql`;
            }

            # User id's may have changed
            `chown -R www-data:www-data /var/www/html`;

            # Set management link
            #`curl -k -X PUT --data-urlencode "PUTDATA={\\"uuid\\":\\"this\\",\\"managementlink\\":\\"/steamengine/pipe/http://{uuid}:10000/origo/\\"}" https://10.0.0.1/steamengine/images`;

            chomp $res;
        }

        $res = "Not copying $srcloc/* -> $dumploc" unless ($res);
        return $res;

    } elsif ($action eq 'loopremove' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $dom = $wp;
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io$/);
        $wpname =~ tr/\./_/;
        $wp = $1 if ($wp =~ /(.+)\.origo\.io$/);
        $dom = "$dom.origo.io" unless ($dom =~ /\./ || $dom eq 'default');
        my $db = "os2loop_$wpname";
        $message .= `mysqldump $db > /$db.sql`;
        `echo "drop database $db;" | mysql`;

        opendir(DIR,$configdir) or die "Cannot open $configdir\n";
        my @sites = readdir(DIR);
        closedir(DIR);
        # Now remove aliases
        my $target = "$dom";
        foreach my $file (@sites) {
            next unless (-d "$configdir/$file");
            my $fname = $file;
            $fname = $1 if ($fname =~ /(.+)\.origo\.io$/);
            if (-l "$configdir/$file") {
                my $link = readlink("$configdir/$file");
                if ($link eq $target) {
                    unlink ("$configdir/$file");
                    # Remove DNS entry if not a FQDN
                    $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnsdelete\&name=$fname"` unless ($fname =~ /\./);
                }
            }
        }

        if ($dom eq 'default') { # default site should always exist - recreate
            `echo "create database $db;" | mysql`;
            # only delete settings.php, preserve directory
            `rm $configdir/$dom/settings.php`;
        # Change the managementlink property of the image
        #    `curl -k -X PUT --data-urlencode 'PUTDATA={"uuid":"this","managementlink":"/steamengine/pipe/http://{uuid}/home/wp-admin/install.php"}' https://10.0.0.1/steamengine/images`;
            $message .=  "<div class=\"message\">Default site was reset!</div>";
            $message .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/install.php?profile=loopdk&locale=en"; </script>|;
        } else {
            `rm -rf $configdir/$dom`;

            # Remove DNS entry if not a FQDN
            $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnsdelete\&name=$wp"` unless ($wp =~ /\./);

            $postscript .= qq|\$('#nav-tabs a[href="#default-site"]').tab('show');\n|;
            $message .=  "<div class=\"message\">Website $dom was removed!</div>";
            opendir(DIR,"$configdir") or die "Cannot open $configdir\n";
            @wpfiles = readdir(DIR);
            closedir(DIR);
        }
        return $message;

    } elsif ($action eq 'loopcreate' && $in{loopdomain_new}) {
        my $message;
        my $wp = lc $in{loopdomain_new};
        my $wpname = $wp;
        $wp = $1 if ($wp =~ /(.+)\.origo\.io$/);
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io$/);
        $wpname =~ tr/\./_/;
        my $dom = $wp;
        $dom = "$dom.origo.io" unless ($dom =~ /\./ || $dom eq 'default');
        my $db = "os2loop_$wpname";
        if (-d "$configdir/$dom" || $wp eq 'new' || $wp eq 'default') {
            $message .=  "<div class=\"message\">Site $dom already exists!</div>";
        } elsif ($dom =~ /\.origo\.io$/  && !dns_check($wp)) {
            $message .=  "<div class=\"message\">Domain $wp.origo.io is not available!</div>";
        } else {
        # Configure os2loop
            my $target = "$dom";
            $message .= `mkdir $configdir/$target`;
            $message .= `cp $configdir/default/default.settings.php $configdir/$target/settings.php`;
            #$message .= `sed 's///' $configdir/$target/settings.php`;
            $message .= `chown -R www-data:www-data $configdir/$target`;
            #$message .= `perl -pi -e 's/os2loop_default/$db/;' /var/www/html/sites/$target/settings.php`;
            #$message .= `perl -pi -e 's/wordpress\\\/wp-content/wordpress\\\/wp-content\\\/blogs.dir\\\/$wpname/;' /etc/wordpress/$target`;
            #$message .= `perl -pi -e 's/home\\\/wp-content/home\\\/wp-content\\\/blogs.dir\\\/$wpname/;' /etc/wordpress/$target`;
            #my $wpc2 = "/var/lib/wordpress/blogs.dir/$wpname";
            #`mkdir $wpc2; chown www-data:www-data $wpc2`;
            #my $wphome = '/usr/share/wordpress/wp-content';
            #`cp -a $wphome/index.php $wphome/languages/ $wphome/plugins/ $wphome/themes/ /var/lib/wordpress/blogs.dir/$wpname`;
        # Create WordPress database
            `echo "create database $db;" | mysql`;
        # Create DNS entry if not a FQDN
            $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscreate\&name=$wp\&value=$externalip.origo.io"` unless ($wp =~ /\./);

        # Create aliases
            if (defined $in{"wpaliases_new"}) {
                my @wpaliases = split(' ', $in{"wpaliases_new"});
                foreach my $alias (@wpaliases) {
                    my $dom1 = $alias;
                    $dom1 = "$alias.origo.io" unless ($alias =~ /\./);
                    $alias = $1 if ($alias =~ /(.+)\.origo\.io/);
                    my $link = "$configdir/$dom1";
                    unless (-e $link) {
                        $message .= `cd $configdir; ln -s "$target" "$link"`;
                        # Create DNS entry if not a FQDN
                        $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscreate\&name=$alias\&value=$externalip.origo.io"` unless ($alias =~ /\./);
                        $message .=  "<div class=\"message\">alias $target -> $link was created!</div>";
                    }
                }
            }

            $message .=  "<div class=\"message\">Website $dom was created!</div>";
            $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
            $message .=  qq|<script>loc=document.location.href; document.location=$wp + "/install.php?profile=loopdk&locale=en"; </script>|;
        }
        return $message;

    } elsif ($action eq 'wpaliases' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wp = $1 if ($wp =~ /(.+)\.origo\.io$/);
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io$/);
        $wpname =~ tr/\./_/;
        my $dom = $wp;
        $dom = "$dom.origo.io" unless ($dom =~ /\./ || $dom eq 'default');
        opendir(DIR,"$configdir") or die "Cannot open $configdir\n";
        my @sites = readdir(DIR);
        closedir(DIR);
        my %aliases;
        if (defined $in{"wpaliases_$wpname"}) {
            my $target = "$dom";
            if (-e "$configdir/$target" && !(-l "$configdir/$target")) {
                my @wpaliases = split(' ', $in{"wpaliases_$wpname"});
                foreach my $alias (@wpaliases) {$aliases{$alias} = 1;}
                # First locate and unlink existing aliases that should be deleted
                foreach my $file (@sites) {
                    next unless (-d "$configdir/$file");
                    my $fname = $file;
                    $fname = $1 if ($file =~ /(.+)\.origo\.io/);
                    if (-l "$configdir/$file") {
                        my $link = readlink("$configdir/$file");
                        if ($link eq $target) {
                            unless ($aliases{$fname} || $aliases{$dom}) { # This alias should be deleted
                                unlink ("$configdir/$file");
                                # Remove DNS entry if not a FQDN
                                $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnsdelete\&name=$fname"` unless ($fname =~ /\./);
                                $message .=  "<div class=\"message\">Alias $file removed!</div>";
                            }
                            $aliases{$fname} = 0; # No need to recreate this alias
                        }
                    }
                }
                # Then create aliases
                foreach my $alias (@wpaliases) {
                    my $newdom = $alias;
                    $newdom = "$alias.origo.io" unless ($alias =~ /\./);
                    $alias = $1 if ($alias =~ /(.+)\.origo\.io$/);
                    my $link = "$configdir/$newdom";
                    # Check availability of new domain names
                    if ($newdom =~ /\.origo\.io$/ && !(-e $link) && !dns_check($newdom)) {
                        $message .=  "<div class=\"message\">Domain $alias.origo.io is not available!</div>";
                    } elsif (($aliases{$alias} || $aliases{$newdom}) && !(-e $link)) {
                        $message .= `cd $configdir; ln -s "$dom" "$link"`;
                        # Create DNS entry if not a FQDN
                        $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscreate\&name=$alias\&value=$externalip.origo.io"` unless ($alias =~ /\./);
    #                    $message .=  "<div class=\"message\">Alias $alias created!</div>";
                # Re-read directory
                    } else {
    #                    $message .=  "<div class=\"message\">Alias $alias not created!</div>";
                    }
                }
                opendir(DIR,"$configdir") or die "Cannot open $configdir\n";
                @wpfiles = readdir(DIR);
                closedir(DIR);
                $message .=  "<div class=\"message\">Aliases updated for $wp!</div>";
            } else {
                $message .=  "<div class=\"message\">Target $target does not exist!</div>";
            }
        }
        return $message;

    } elsif ($action eq 'wprestore' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
        $wpname =~ tr/\./_/;
        my $db = "os2loop_$wpname";
        if (-e "/$db.sql") {
    #        `echo "drop database wordpress; create database wordpress;" | mysql`;
            $message .=  `mysql $db < /$db.sql`;
            if (`echo status | mysql $db`) {
                $message .=  "<div class=\"message\">Database restored.</div>";
            } else {
                $message .=  "<div class=\"message\">Database $db not found!</div>";
            }
        }
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;

        #} elsif ($action eq 'wpbackup' && $in{wp}) {
        #my $message;
        #my $wp = $in{wp};
        #my $wpname = $wp;
        #$wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
        #$wpname =~ tr/\./_/;
        #my $db = "os2loop_$wpname";
        #$message .=  `mysqldump $db > /$db.sql`;
        #$message .=  "<div class=\"message\">WordPress database was backed up!</div>" if (-e "/$db.sql");
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
    #return $message;
    } elsif ($action eq 'wppassword' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wpname =~ tr/\./_/;
        my $db = "os2loop_$wpname";
        my $pwd = $in{wppassword};
        $pwd = `/var/www/html/scripts/password-hash.sh $pwd`;
        if ($pwd) {
            $message .=  `echo "UPDATE users SET pass = $pwd WHERE ID = 1;" | mysql -s $db`;
            $message .=  "<div class=\"message\">The password was changed!</div>";
        }
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;
        } elsif ($action eq 'looplimit') {
            #my $message;
            #if (defined $in{wplimit}) {
            #my $limit = $in{wplimit};
            #my ($validlimit, $mess) = validate_limit($limit);
            #$message .= $mess;
            #if ($validlimit) {
            #    if (`grep '#origo' $drupalroot/.htaccess`) {
            #        $message .= `perl -pi -e 's/allow from (.*) \#origo/allow from $validlimit #origo/;' $drupalroot/.htaccess`;
            #    } else {
            #        $validlimit =~ s/\\//g;
            #        `echo '<Files ~ "admin">\norder allow deny\ndeny from all\nallow from $validlimit #origo\n</Files>' >> $drupalroot/.htaccess`;
            #    }
            #    $message .=  "<div class=\"message\">OS2Loop admin access was changed!</div>";
            #} else {
            #    $message .= `perl -i -p0e 's/<files wp-login\.php>\n.*\n.*\n.*\n<\/files>//smg' /usr/share/wordpress/.htaccess`;
            #    $message .=  "<div class=\"message\">OS2Loop admin access is now open from anywhere!</div>";
            #    $wplimit = '';
            #}
            #my $allow = `cat $drupalroot/.htaccess`;
            #$wplimit = $1 if ($allow =~ /allow from (.+) \#origo/);
            #}
            #return $message;
        }
}

1;
