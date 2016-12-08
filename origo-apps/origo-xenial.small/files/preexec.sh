#!/bin/bash

echo "Performing pre-install operations"
bash -c 'echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository sarge contrib" >> /etc/apt/sources.list'
wget http://www.webmin.com/jcameron-key.asc
apt-key add jcameron-key.asc
apt-get update
# Stop local webmin from blocking port 10000
`systemctl stop webmin`
apt-get -q -y --force-yes install webmin
# Set up automatic scanning for other Webmin servers
bash -c 'echo "auto_pass=origo
auto_self=1
auto_smtp=
auto_net=ens3
auto_type=ubuntu
auto_cluster-software=1
auto_remove=1
auto_user=origo
scan_time=10
resolve=0
auto_email=" > /etc/webmin/servers/config'
# Allow unauthenticated access to origo module
bash -c 'echo "anonymous=/origo=origo" >> /etc/webmin/miniserv.conf'
# Disable Webmin SSL
perl -pi -e "s/ssl=1/ssl=0/g;" /etc/webmin/miniserv.conf
# Scan every 5 minutes for other Webmin servers
perl -pi -e "s/(\{\'notfound\'\}\+\+ >=) 3/\$1 1/;" /usr/share/webmin/servers/auto.pl
bash -c 'echo "#!/usr/bin/perl
open(CONF, qq[/etc/webmin/miniserv.conf]) || die qq[Failed to open /etc/webmin/miniserv.conf : \$!];
while(<CONF>) {
    \$root = \$1 if (/^root=(.*)/);
    }
close(CONF);
\$root || die qq[No root= line found in /etc/webmin/miniserv.conf];
\$ENV{PERLLIB} = \$root;
\$ENV{WEBMIN_CONFIG} = qq[/etc/webmin];
\$ENV{WEBMIN_VAR} = qq[/var/webmin];
chdir(qq[\$root/servers]);
exec(qq[\$root/servers/auto.pl], @ARGV) || die qq[Failed to run \$root/servers/auto.pl : \$!];" > /etc/webmin/servers/auto.pl'

chmod 755 /etc/webmin/servers/auto.pl
# For now - disable automatic scanning
#	bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /etc/webmin/servers/auto.pl") | crontab'
# Enable auto registering instead
bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /usr/local/bin/origo-ubuntu.pl") | crontab'
# Disable Webmin referer check
perl -pi -e "s/referers_none=1/referers_none=0/;" /etc/webmin/config
bash -c 'echo "webprefix=
referer=1
referers=" >> /etc/webmin/config'
# Change fstab since we are using virtio
perl -pi -e "s/sda/vda/g;" /etc/fstab

# Simple script to start shellinabox
bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Shellinabox for Origo Compute

[Service]
ExecStart=/usr/share/webmin/origo/tabs/servers/shellinaboxd -b -t -n --no-beep
TimeoutSec=15
RemainAfterExit=yes
Type=forking

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/origo-shellinabox.service'
chmod 664 /etc/systemd/system/origo-shellinabox.service
# Start webmin again
`systemctl start webmin`
