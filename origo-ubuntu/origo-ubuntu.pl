#!/usr/bin/perl

use JSON;
use Text::ParseWords;
use Data::Dumper;

my $registered;
my $internalip;
my $i;

my $action = shift if $ARGV[0];

if ($action eq 'mountpools') {
    print `curl --silent http://localhost:10000/origo/index.cgi?action=mountpools`;
    exit 0;
} elsif  ($action eq 'initapps') {
    print `curl --silent http://localhost:10000/origo/index.cgi?action=initapps`;
    exit 0;
} elsif  ($action eq 'activateapps') {
    print `curl --silent http://localhost:10000/origo/index.cgi?action=activateapps`;
    exit 0;
}

if (-e '/etc/webmin/') {
    while (!$registered && $i<20) {
        $internalip = `cat /tmp/internalip` if (-e '/tmp/internalip');
        $internalip = `cat /etc/origo/internalip` if (-e '/etc/origo/internalip');
        chomp $internalip;
        my $res = `curl http://$internalip:10000/origo/index.cgi?action=registerwebminserver`;
        $registered = ($res =~ /Registered at \S+/);
        if ($registered) {
            `echo "$res" >> /tmp/origo-registered`;
        } else {
            `echo "$res" >> /tmp/origo-registered`;
            sleep 5;
        };
        $i++;
    }
} else {
    print "Webmin not installed, not registering server\n";
}

my $appinfo = `curl -ks "https://10.0.0.1/steamengine/servers?action=getappinfo"`;
my $info_ref = from_json($appinfo);
my $status = $info_ref->{status};
my $uuid = $info_ref->{uuid};

if ($status eq 'upgrading') {
    print "Upgrading this server...\n";
    `echo "restoring" > /tmp/restoring` unless ( -e "/tmp/restoring");

    # Mount storage pools and locate source dir
    my $json_text = `curl -ks "https://10.0.0.1/steamengine/images?action=liststoragepools"`;
    my $spools_ref = from_json($json_text);
    my @spools = @$spools_ref;
    my $mounts = `cat /proc/mounts`;
    my @restoredirs;

    my $json_text = `curl -ks "https://10.0.0.1/steamengine/users/me"`;
    if ($json_text =~ /^\[/) {
        my $json_hash_ref = from_json($json_text);
        my $me_ref = $json_hash_ref->[0];
        $user = $me_ref->{username};
    }

    if ($user) {
        foreach my $pool (@spools) {
            next if ($pool->{id} == -1);
            next unless ($pool->{mountable});
            my $sid = "pool" . $pool->{id};
            my $spath = $pool->{path};
            my $shostpath = $pool->{hostpath};
            unless ($mounts =~ /\/mnt\/fuel\/$sid/) {
            `mkdir -p /mnt/fuel/$sid` unless (-e "/mnt/fuel/$sid");
                my $mounted;
                if ($shostpath eq 'local') {
                    $mounted = `mount 10.0.0.1:$spath/$user/fuel /mnt/fuel/$sid`;
                } else {
                    $mounted = `mount $shostpath/$user/fuel /mnt/fuel/$sid`;
                }
            }
            my $srcloc = "/mnt/fuel/$sid/upgradedata/$uuid";
            push @restoredirs, $srcloc if (-e $srcloc); # If upgrade data exists, restore from this dir
        }
        # Read in libs for tabs
        opendir(DIR,"/usr/share/webmin/origo/tabs") or die "Cannot open tabs directory\n";
        my @dir = readdir(DIR);
        closedir(DIR);
        my @tabs;
        foreach my $tab (@dir) {
            next if ($tab =~ /\./);
            print "Sourcing $tab-lib.pl\n" if (-e "/usr/share/webmin/origo/tabs/$tab/$tab-lib.pl");
            require "/usr/share/webmin/origo/tabs/$tab/$tab-lib.pl";
        }

        # Ask each library to do the actual restore
        foreach my $tab (@dir) {
            next if ($tab =~ /\./);
            foreach my $srcloc (@restoredirs) {
                my $res = $tab->("restore", {sourcedir=>$srcloc}) if (defined &$tab && $srcloc);
                $res =~ s/\n/ /g;
                print "$tab, $srcloc: $res\n";
                `echo "$res" >> /tmp/restore.log`;
            }
        }
    } else {
        print "Unable to get user.\n";
    }

    unlink ("/tmp/restoring");
    # Done copying data back, change status from upgrading to running
    print `curl -ks "https://10.0.0.1/steamengine/servers?action=setrunning"`;

} else {
    print "Server is $status. Not upgrading this server...\n";
    if (-e '/usr/share/webmin/origo/tabs/servers/shellinaboxd') {
        unless (`pgrep shellinaboxd`) {
            print "Starting shellinabox...\n";
            # Disallow shellinabox access from outside
            my $gw = $internalip;
            $gw = "$1.1" if ($gw =~ /(\d+\.\d+\.\d+)\.\d+/);
            print `iptables -D INPUT -p tcp --dport 4200 -s $gw -j ACCEPT`;
            print `iptables -D INPUT -p tcp --dport 4200 -j DROP`;
            print `iptables -A INPUT -p tcp --dport 4200 -s $gw -j ACCEPT`;
            print `iptables -A INPUT -p tcp --dport 4200 -j DROP`;
#            `screen -d -m /usr/share/webmin/origo/tabs/servers/shellinaboxd -t -n --no-beep`;
            `/usr/share/webmin/origo/tabs/servers/shellinaboxd -b -t -n --no-beep`;
        }
    }
}
