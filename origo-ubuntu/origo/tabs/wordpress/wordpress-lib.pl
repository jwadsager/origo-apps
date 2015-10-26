#!/usr/bin/perl

use JSON;

sub wordpress {
    my $action = shift;
    my $in_ref = shift;
    my %in = %{$in_ref};

    if ($action eq 'form') {
# Generate and return the HTML form for this tab

    # First let's make sure install.php has been patched - WP may have been upgraded
        unless (`grep "HTTP_HOST" /usr/share/wordpress/wp-admin/install.php`) {
            `/usr/local/bin/origo-wordpress.sh`;
#            system(q|perl -pi -e 's/(\/\/ Sanity check\.)/$1\n\$showsite=( (strpos(\$_SERVER[HTTP_HOST], ".origo.io")===FALSE)? \$_SERVER[HTTP_HOST] : substr(\$_SERVER[HTTP_HOST], 0, strpos(\$_SERVER[HTTP_HOST], ".origo.io")) );\n/' /usr/share/wordpress/wp-admin/install.php|);
#            system(q|perl -pi -e 's/(^<p class="step"><a href="\.\.\/wp-login\.php".+<\/a>)/<!-- $1 --><script>var pipeloc=location\.href\.substring(0,location.href.indexOf("\/home")); location=pipeloc \+ ":10000\/origo\/?show=<?php echo \$showsite; ?>-site";<\/script>/;'  /usr/share/wordpress/wp-admin/install.php|);
            # Crazy amount of escaping required
#            system(qq|perl -pi -e "s/(step=1)/\\\$1\&host=' \. \\\\\\\$_SERVER[HTTP_HOST] \.'/;" /usr/share/wordpress/wp-admin/install.php|);
#            system(q|perl -pi -e 's/(step=2)/$1\&host=<?php echo \$_SERVER[HTTP_HOST]; ?>/;' /usr/share/wordpress/wp-admin/install.php|);
        } else {
            ;# "Already patched\n";
        }

        my $form;
        opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
        my @wpfiles = readdir(DIR);
        closedir(DIR);
        my %aliases;
        foreach my $file (@wpfiles) {
            next unless ($file =~ /config-(.+)\.php/);
            if (-l "/etc/wordpress/$file") {
                my $link = readlink("/etc/wordpress/$file");
                $aliases{$link} .= "$1 ";
            }
        }

        foreach my $file (@wpfiles) {
            next if (-l "/etc/wordpress/$file");
            next unless ($file =~ /config-(.+)\.php/);
            my $wp = $1;
            my $wpname = $wp;
            $wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
            $wpname =~ tr/\./_/;
            $form .= getWPtab($wp, $wpname, $aliases{$file});
        }
        $form .=  getWPtab('new', 'new');
        $form .=  getWPtab('wpsecurity', 'wpsecurity');

        # Redirect to upgrade page if still upgrading
        if (-e "/tmp/restoring") {
            $form .=  qq|<script>loc=document.location.href; setTimeout(function(){document.location=loc;}, 1500); </script>|;
        # Redirect to WordPress install page if default site not configured
        } elsif (!(`echo "SHOW TABLES LIKE 'wp_posts'" | mysql wordpress_default`)) {
            $form .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/home/wp-admin/install.php?host=default"; </script>|;
        }

        return $form;

    } elsif ($action eq 'js') {
# Generate and return javascript the UI for this tab needs
        my $js = <<END
        \$('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            var site = e.target.id;
            var href = e.target.href;
            var regexp = /#(.+)-site/;
            var match = regexp.exec(href);
            if (href.indexOf('#new')!=-1) { // set standard grey border in case it has failed validation previously
                \$('#wpdomain_new').css('border','1px solid #CCCCCC'); \$('#wpdomain_new').focus();
            }
            \$("#currentwpadmin").parent().show();
            if (!match || match[1] == 'default' || match[1] == 'new') {
                \$("#currentwp").attr("href", "http://$externalip/");
                \$("#currentwp").text("to default WordPress website");
                \$("#currentwpadmin").attr("href", "https://$externalip/home/wp-admin/");
                \$("#currentwpadmin").text("to default WordPress console");
            } else {
                var siteaddr = site;
                if (site.indexOf(".")==-1) siteaddr = site + ".origo.io"
                \$("#currentwp").attr("href", "http://" + siteaddr + "/");
                \$("#currentwp").text("to " + site + " website");
                \$("#currentwpadmin").attr("href", "https://" + siteaddr + "/home/wp-admin/");
                \$("#currentwpadmin").text("to " + site + " administration");
            }
            if (match) {
                if (\$("#wpaliases_" + match[1]).val() == '--')
                    \$("#wpaliases_" + match[1]).val("");
                \$("#wppassword_" + match[1]).val("");
            }
        })

        \$(".wpdomain").keypress(function(event){
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
            if (action == 'wpremove') {
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
        return getWPdropdown();

# This is called from index.cgi (the UI)
    } elsif ($action eq 'upgrade') {
        my $res;
        my $srcloc = "/usr/share/wordpress/wp-content";
        my $dumploc = $in{targetdir};

        if (-d $dumploc) {
            # Dump database
            `mysqldump --databases \$(mysql -N information_schema -e "SELECT DISTINCT(TABLE_SCHEMA) FROM tables WHERE TABLE_SCHEMA LIKE 'wordpress_%'") > $dumploc/wordpress.sql`;
            # Copy wp-content (remove target first, in order to be able to compare sizes)
            `rm -r $dumploc/wp-content`;
            `cp -r $srcloc $dumploc`;
            `rm -r $dumploc/blogs.dir`;
            `cp -r /var/lib/wordpress/blogs.dir $dumploc`;
            # Also copy /etc/wordpress
            `cp -r /etc/wordpress $dumploc`;
        }

        my $srcsize = `du -bs $srcloc`;
        $srcsize = $1 if ($srcsize =~ /(\d+)/);
        my $dumpsize = `du -bs $dumploc/wp-content`;
        $dumpsize = $1 if ($dumpsize =~ /(\d+)/);
        if ($srcsize == $dumpsize) {
            $res = "OK: WordPress data and database dumped successfully to $dumploc";
        } else {
            $res = "There was a problem dumping WordPress data to $dumploc ($srcsize <> $dumpsize)!";
        }
        return $res;

# This is called from origo-ubuntu.pl when rebooting and with status "upgrading"
    } elsif ($action eq 'restore') {
        my $srcloc = $in{sourcedir};
        my $res;
        my $dumploc  = "/usr/share/wordpress/wp-content/";
        if (-d $srcloc && -d $dumploc) {
            $res = "OK: ";

            $srcdir = "wp-content/*";
            $dumploc  = "/usr/share/wordpress/wp-content/";
            $res .= qq|copying $srcloc/$srcdir -> $dumploc, |;
            $res .= `cp --backup -a $srcloc/$srcdir "$dumploc"`;
            $res .= `chown -R www-data:www-data $dumploc`;

            $srcdir = "blogs.dir/*";
            $dumploc  = "/var/lib/wordpress/blogs.dir/";
            $res .= qq|copying $srcloc/$srcdir -> $dumploc, |;
            $res .= `cp --backup -a $srcloc/$srcdir "$dumploc"`;
            $res .= `chown -R www-data:www-data $dumploc`;

            $srcdir = "wordpress/*";
            $dumploc  = "/etc/wordpress/";
            $res .= qq|copying $srcloc/$srcdir -> $dumploc, |;
            $res .= `cp --backup -a $srcloc/$srcdir "$dumploc"`;

            if (-e "$srcloc/wordpress.sql") {
                $res .= qq|restoring db, |;
                $res .= `/usr/bin/mysql < $srcloc/wordpress.sql`;
            }

            # User id's may have changed
            `chown -R www-data:www-data /usr/share/wordpress`;

            # Set management link
#            `curl -k -X PUT --data-urlencode "PUTDATA={\\"uuid\\":\\"this\\",\\"managementlink\\":\\"/steamengine/pipe/http://{uuid}:10000/origo/\\"}" https://10.0.0.1/steamengine/images`;

            chomp $res;
        }

        $res = "Not copying $srcloc/* -> $dumploc" unless ($res);
        #`/etc/init.d/apache2 start`;
        #`umount /mnt/fuel/*`;
        return $res;

    } elsif ($action eq 'wpremove' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $dom = $wp;
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io$/);
        $wpname =~ tr/\./_/;
        $wp = $1 if ($wp =~ /(.+)\.origo\.io$/);
        $dom = "$dom.origo.io" unless ($dom =~ /\./ || $dom eq 'default');
        my $db = "wordpress_$wpname";
        $message .= `mysqldump $db > /var/lib/wordpress/$db.sql`;
        `echo "drop database $db;" | mysql`;

        opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
        my @wpfiles = readdir(DIR);
        closedir(DIR);
        # Now remove aliases
        my $target = "config-$dom.php";
        foreach my $file (@wpfiles) {
            next unless ($file =~ /config-(.+)\.php/);
            my $fname = $1;
            $fname = $1 if ($fname =~ /(.+)\.origo\.io$/);
            if (-l "/etc/wordpress/$file") { # Check if it is a link
                my $link = readlink("/etc/wordpress/$file");
                if ($link eq $target) {
                    unlink ("/etc/wordpress/$file");
                    # Remove DNS entry if not a FQDN
                    $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnsdelete\&name=$fname"` unless ($fname =~ /\./);
                }
            }
        }

        if ($dom eq 'default') { # default should always exist - recreate
            `echo "create database $db;" | mysql`;
        # Change the managementlink property of the image
        #    `curl -k -X PUT --data-urlencode 'PUTDATA={"uuid":"this","managementlink":"/steamengine/pipe/http://{uuid}/home/wp-admin/install.php"}' https://10.0.0.1/steamengine/images`;
            $message .=  "<div class=\"message\">Default website was reset!</div>";
            $message .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/home/wp-admin/install.php?host=$dom"; </script>|;
        } else {
            unlink("/etc/wordpress/config-$dom.php");
            my $wpc2 = "/var/lib/wordpress/blogs.dir/$wpname";
            `rm -r "$wpc2"`;

            # Remove DNS entry if not a FQDN
            $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnsdelete\&name=$wp"` unless ($wp =~ /\./);

            $postscript .= qq|\$('#nav-tabs a[href="#default-site"]').tab('show');\n|;
            $message .=  "<div class=\"message\">Website $dom was removed!</div>";
            opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
            @wpfiles = readdir(DIR);
            closedir(DIR);
        }
        return $message;
    } elsif ($action eq 'wpcreate' && $in{wpdomain_new}) {
        my $message;
        my $wp = $in{wpdomain_new};
        my $wpname = $wp;
        $wp = $1 if ($wp =~ /(.+)\.origo\.io$/);
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io$/);
        $wpname =~ tr/\./_/;
        my $dom = $wp;
        $dom = "$dom.origo.io" unless ($dom =~ /\./ || $dom eq 'default');
        my $db = "wordpress_$wpname";
        if (-e "/etc/wordpress/config-$dom.php" || $wp eq 'new' || $wp eq 'default') {
            $message .=  "<div class=\"message\">Website $dom already exists!</div>";
     #       $postscript .= qq|\$('#nav-tabs a[href="#new-site"]').tab('show');\n|;
        } elsif ($dom =~ /\.origo\.io$/  && !dns_check($wp)) {
            $message .=  "<div class=\"message\">Domain $wp.origo.io is not available!</div>";
        } else {
        # Configure WordPress / Debian
            my $target = "config-$dom.php";

            $message .= `cp /etc/wordpress/config-default.php /etc/wordpress/$target`;
            $message .= `perl -pi -e 's/wordpress_default/$db/;' /etc/wordpress/$target`;
            $message .= `perl -pi -e 's/wordpress\\\/wp-content/wordpress\\\/wp-content\\\/blogs.dir\\\/$wpname/;' /etc/wordpress/$target`;
            $message .= `perl -pi -e 's/home\\\/wp-content/home\\\/wp-content\\\/blogs.dir\\\/$wpname/;' /etc/wordpress/$target`;
            my $wpc2 = "/var/lib/wordpress/blogs.dir/$wpname";
            `mkdir $wpc2; chown www-data:www-data $wpc2`;
            my $wphome = '/usr/share/wordpress/wp-content';
            `cp -a $wphome/index.php $wphome/languages/ $wphome/plugins/ $wphome/themes/ /var/lib/wordpress/blogs.dir/$wpname`;
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
                    my $link = "/etc/wordpress/config-$dom1.php";
                    unless (-e $link) {
                        $message .= `cd /etc/wordpress; ln -s "$target" "$link"`;
                        # Create DNS entry if not a FQDN
                        $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscreate\&name=$alias\&value=$externalip.origo.io"` unless ($alias =~ /\./);
                        $message .=  "<div class=\"message\">alias $target -> $link was created!</div>";
                    }
                }
            }

            $message .=  "<div class=\"message\">Website $dom was created!</div>";
            $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
            $message .=  qq|<script>loc=document.location.href; document.location=loc.substring(0,loc.indexOf(":10000")) + "/home/wp-admin/install.php?host=$dom"; </script>|;
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
        opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
        my @wpfiles = readdir(DIR);
        closedir(DIR);
        my %aliases;
        if (defined $in{"wpaliases_$wpname"}) {
            my $target = "config-$dom.php";
            if (-e "/etc/wordpress/$target" && !(-l "/etc/wordpress/$target")) {
                my @wpaliases = split(' ', $in{"wpaliases_$wpname"});
                foreach my $alias (@wpaliases) {$aliases{$alias} = 1;}
                # First locate and unlink existing aliases that should be deleted
                foreach my $file (@wpfiles) {
                    next unless ($file =~ /config-(.+)\.php/);
                    my $dom = $1;
                    my $fname = $dom;
                    $fname = $1 if ($dom =~ /(.+)\.origo\.io/);
                    if (-l "/etc/wordpress/$file") {
                        my $link = readlink("/etc/wordpress/$file");
                        if ($link eq $target) {
                            unless ($aliases{$fname} || $aliases{$dom}) { # This alias should be deleted
                                unlink ("/etc/wordpress/$file");
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
                    my $link = "/etc/wordpress/config-$newdom.php";
                    # Check availability of new domain names
                    if ($newdom =~ /\.origo\.io$/ && !(-e $link) && !dns_check($newdom)) {
                        $message .=  "<div class=\"message\">Domain $alias.origo.io is not available!</div>";
                    } elsif (($aliases{$alias} || $aliases{$newdom}) && !(-e $link)) {
                        $message .= `cd /etc/wordpress; ln -s "config-$dom.php" "$link"`;
                        # Create DNS entry if not a FQDN
                        $message .= `curl -k --max-time 5 "https://10.0.0.1/steamengine/networks?action=dnscreate\&name=$alias\&value=$externalip.origo.io"` unless ($alias =~ /\./);
    #                    $message .=  "<div class=\"message\">Alias $alias created!</div>";
                # Re-read directory
                    } else {
    #                    $message .=  "<div class=\"message\">Alias $alias not created!</div>";
                    }
                }
                opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
                @wpfiles = readdir(DIR);
                closedir(DIR);
                $message .=  "<div class=\"message\">Aliases updated for $wp!</div>";
            } else {
                $message .=  "<div class=\"message\">Target $target does not exist!</div>";
            }
        }
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;
    } elsif ($action eq 'wprestore' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
        $wpname =~ tr/\./_/;
        my $db = "wordpress_$wpname";
        if (-e "/var/lib/wordpress/$db.sql") {
    #        `echo "drop database wordpress; create database wordpress;" | mysql`;
            $message .=  `mysql $db < /var/lib/wordpress/$db.sql`;
            if (`echo status | mysql $db`) {
                $message .=  "<div class=\"message\">WordPress database restored.</div>";
            } else {
                $message .=  "<div class=\"message\">WordPress database $db not found!</div>";
            }
        }
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;
    } elsif ($action eq 'wpbackup' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
        $wpname =~ tr/\./_/;
        my $db = "wordpress_$wpname";
        $message .=  `mysqldump $db > /var/lib/wordpress/$db.sql`;
        $message .=  "<div class=\"message\">WordPress database was backed up!</div>" if (-e "/var/lib/wordpress/$db.sql");
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;
    } elsif ($action eq 'wppassword' && $in{wp}) {
        my $message;
        my $wp = $in{wp};
        my $wpname = $wp;
        $wpname =~ tr/\./_/;
        my $db = "wordpress_$wpname";
        my $pwd = $in{wppassword};
        if ($pwd) {
            $message .=  `echo "UPDATE wp_users SET user_pass = MD5('$pwd') WHERE ID = 1;" | mysql -s $db`;
            $message .=  "<div class=\"message\">The WordPress password was changed!</div>";
        }
    #    $postscript .= qq|\$('#nav-tabs a[href="#$wpname-site"]').tab('show');\n|;
        return $message;
    } elsif ($action eq 'wplimit') {
        my $message;
        if (defined $in{wplimit}) {
            my $limit = $in{wplimit};
            my ($validlimit, $mess) = validate_limit($limit);
            $message .= $mess;
            if ($validlimit) {
                if (`grep '#origo' /usr/share/wordpress/.htaccess`)
                {
                    $message .= `perl -pi -e 's/allow from (.*) \#origo/allow from $validlimit #origo/;' /usr/share/wordpress/.htaccess`;
                } else {
                    $validlimit =~ s/\\//g;
                    `echo "<files wp-login.php>\norder deny,allow\ndeny from all\nallow from $validlimit #origo\n</files>" >> /usr/share/wordpress/.htaccess`;
                }
                $message .=  "<div class=\"message\">WordPress admin access was changed!</div>";
            } else {
                $message .= `perl -i -p0e 's/<files wp-login\.php>\n.*\n.*\n.*\n<\/files>//smg' /usr/share/wordpress/.htaccess`;
                $message .=  "<div class=\"message\">WordPress admin access is now open from anywhere!</div>";
                $wplimit = '';
            }
            my $allow = `cat /usr/share/wordpress/.htaccess`;
            $wplimit = $1 if ($allow =~ /allow from (.+) \#origo/);
        }
        return $message;
    }
}

## Returns HTML for drop-down for selecting WordPress sites
sub getWPdropdown {
    my $websitedrops;
    opendir(DIR,"/etc/wordpress") or die "Cannot open /etc/wordpress\n";
    my @wpfiles = readdir(DIR);
    closedir(DIR);

    foreach my $file (@wpfiles) {
        next if (-l "/etc/wordpress/$file"); # This is an alias - skip
        next unless ($file =~ /config-(.+)\.php/);
        my $wp = $1;
        next if $wp eq 'default';
        my $wpname = $wp;
        $wpname = $1 if ($wpname =~ /(.+)\.origo\.io/);
        $wpname =~ tr/\./_/;
        $websitedrops .= <<END
<li><a href="#$wpname-site" tabindex="-1" data-toggle="tab" id="$wp">$wp</a></li>
END
;
    }

    my $dropdown = <<END
        <li class="dropdown">
            <a href="#" id="myTabDrop1" class="dropdown-toggle" data-toggle="dropdown">wordpress <b class="caret"></b></a>
            <span class="dropdown-arrow"></span>
            <ul class="dropdown-menu" role="menu" aria-labelledby="myTabDrop1">
                <li><a href="#default-site" tabindex="-1" data-toggle="tab">Default website</a></li>
                $websitedrops
                <li><a href="#new-site" tabindex="-1" data-toggle="tab">Add new website...</a></li>
                <li><a href="#wp-security" tabindex="-1" data-toggle="tab">WordPress security</a></li>
            </ul>
        </li>
END
;
    return $dropdown;

}

## Returns HTML for a single WordPress configuration tab
sub getWPtab {
    my $wp = shift;
    my $wpname = shift;
    my $wpaliases = shift;
    $wpaliases = join(' ', split(' ', $wpaliases));

    my $wpuser;
    if ($wp eq 'new') {
        $wpuser = "admin";
    } elsif ($wp eq 'wpsecurity') {

        my $allow = `cat /etc/hosts.allow`;
        my $wplimit;
        $wplimit = $1 if ($allow =~ /allow from (.+) \#origo/);

        my $curipwp;
        $curipwp = qq|<span style="float: left; font-size: 13px;">leave empty to allow login from anywhere, your current IP is <a href="#" onclick="\$('#wplimit').val('$ENV{HTTP_X_FORWARDED_FOR} ' + \$('#wplimit').val());">$ENV{HTTP_X_FORWARDED_FOR}</a></span>| if ($ENV{HTTP_X_FORWARDED_FOR});

        my $wpsecurityform = <<END
<div class="tab-pane" id="wp-security">
    <form class="passwordform" action="index.cgi?action=wplimit\&tab=wordpress\&show=wp-security" method="post" accept-charset="utf-8" style="margin-bottom:36px;">
        <small>Limit wordpress login for all sites to:</small>
        <input id="wplimit" type="text" name="wplimit" value="$wplimit" placeholder="IP address or network, e.g. '192.168.0.0/24 127.0.0.1'">
        $curipwp
        <button class="btn btn-default" type="submit" onclick="spinner(this);">Set!</button>
    </form>
</div>
END
;
        return $wpsecurityform;
    } else {
        my $db = "wordpress_$wpname";
        $wpuser = `echo "select user_login from wp_users where id=1;" | mysql -s $db`;
        chomp $wpuser;
        $wpuser = $wp unless ($wpuser);
    }

    my $resetbutton = qq|<button class="btn btn-danger" rel="tooltip" data-placement="top" title="This will remove your website and wipe your database - be absolutely sure this is what you want to do!" onclick="confirmWPAction('wpremove', '$wpname');" type="button">Remove website</button>|;

    my $backup_tooltip = "Click to back up your WordPress database";
    $wpaliases = '--' unless ($wpaliases);

    my $manageform = <<END
    <div class="tab-pane" id="$wpname-site">
    <form class="passwordform wpform" id="wpform_$wpname" action="index.cgi?tab=wordpress\&show=$wpname-site" method="post" accept-charset="utf-8">
        <div>
            <small>The website's domain name:</small>
            <input class="wpdomain" id="wpdomain_$wpname" type="text" name="wpdomain_$wpname" value="$wp" disabled autocomplete="off">
        </div>
        <div>
            <small>Aliases for the website:</small>
            <input class="wpalias" id="wpaliases_$wpname" type="text" name="wpaliases_$wpname" value="$wpaliases" autocomplete="off">
            <button class="btn btn-default" onclick="spinner(this); \$('#action_$wpname').val('wpaliases');" rel="tooltip" data-placement="top" title="Aliases that are not FQDNs will be created in the origo.io domain as [alias].origo.io">Set!</button>
        </div>
        <div>
            <small>Set password for WordPress user '$wpuser':</small>
            <input id="wppassword_$wpname" type="password" name="wppassword" autocomplete="off" value="" class="password">
            <button class="btn btn-default" onclick="spinner(this); \$('#action_$wpname').val('wppassword');">Set!</button>
        </div>
    <div style="height:10px;"></div>
END
;

    my $backupbutton = qq|<button class="btn btn-primary" rel="tooltip" data-placement="top" title="$backup_tooltip" onclick="\$('#action_$wpname').val('wpbackup'); \$('#wpform_$wpname').submit(); spinner(this);">Backup database</button>|;

    if ($wp eq 'new') {
        $backup_tooltip = "You must save before you can back up";
        $resetbutton = qq|<button class="btn btn-info" type="button" rel="tooltip" data-placement="top" title="Click to create your new website!" onclick="if (\$('#wpdomain_new').val()) {spinner(this); \$('#action_$wpname').val('wpcreate'); \$('#wpform_$wpname').submit();} else {\$('#wpdomain_new').css('border','1px solid #f39c12'); \$('#wpdomain_new').focus(); return false;}">Create website</button>|;

        $manageform = <<END
    <div class="tab-pane" id="$wp-site">
    <form class="passwordform wpform" id="wpform_$wpname" action="index.cgi?tab=wordpress\&show=$wpname-site" method="post" accept-charset="utf-8">
        <div>
            <small>The website's domain name:</small>
            <input class="wpdomain required" id="wpdomain_$wpname" type="text" name="wpdomain_$wpname" value="" autocomplete="off">
        </div>
        <div>
            <small>Aliases for the website:</small>
            <input class="wpdomain" id="wpaliases_$wpname" type="text" name="wpaliases_$wpname" value="$wpaliases" autocomplete="off">
        </div>
        <div>
            <small>Set password for WordPress user 'admin':</small>
            <input id="wppassword_$wpname" type="password" name="wppassword" autocomplete="off" value="" disabled class="disabled" placeholder="Password can be set after creating website">
            <button class="btn btn-default disabled" disabled>Set!</button>
        </div>
    <div style="height:10px;"></div>
END
;
        $backupbutton = qq|<button class="btn btn-primary disabled" rel="tooltip" data-placement="top" title="$backup_tooltip" onclick="spinner(this); return false;">Backup database</button>|;
    }

    my $restorebutton = qq|<button class="btn btn-primary disabled" rel="tooltip" data-placement="top" title="You must back up before you can restore" onclick="spinner(this); return false;">Restore database</button>|;
    my $ftime;

    if (-e "/var/lib/wordpress/wordpress_$wpname.sql") {
        $ftime = make_date( (stat("/var/lib/wordpress/wordpress_$wpname.sql"))[9] ) . ' ' . `date +%Z`;
        $restorebutton = qq|<button class="btn btn-primary" rel="tooltip" data-placement="top" title="Restore database from backup made $ftime" onclick="spinner(this); \$('#action_$wpname').val('wprestore'); \$('#wpform_$wpname').submit();">Restore database</button>|;
    }

    my $backupform .= <<END
    <div class="mbl">
        $backupbutton
        $restorebutton
        $resetbutton
        <input type="hidden" name="action" id="action_$wpname">
        <input type="hidden" name="wp" id="wp_$wpname" value="$wp">
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

1;
