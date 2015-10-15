#!/bin/bash

# The version of the app we are building
version="1.2"
#dname=`basename "$PWD"`
dname="origo-reference"
me=`basename $0`

# Change working directory to script's directory
cd ${0%/*}

## If we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"
# Stop local webmin from blocking port 10000
	`/etc/init.d/webmin stop`;
# Add multiverse
#    chroot $1 perl -pi -e "s/universe/universe multiverse/;" /etc/apt/sources.list
# Install Webmin
	chroot $1 bash -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list'
	chroot $1 wget http://www.webmin.com/jcameron-key.asc
	chroot $1 apt-key add jcameron-key.asc
	chroot $1 apt-get update
	chroot $1 apt-get -q -y --force-yes install apache2-mpm-prefork libapache2-mod-php5
	chroot $1 apt-get -q -y --force-yes install webmin
# Install IOzone
	chroot $1 apt-get  -q -y --force-yes install iozone3
# Set up automatic scanning for other Webmin servers
	chroot $1 bash -c 'echo "auto_pass=origo
auto_self=1
auto_smtp=
auto_net=eth0
auto_type=ubuntu
auto_cluster-software=1
auto_remove=1
auto_user=origo
scan_time=10
resolve=0
auto_email=" > /etc/webmin/servers/config'
# Allow unauthenticated access to ubuntu module
	chroot $1 bash -c 'echo "anonymous=/origo=origo" >> /etc/webmin/miniserv.conf'
# Disable Webmin SSL
	chroot $1 perl -pi -e "s/ssl=1/ssl=0/g;" /etc/webmin/miniserv.conf
# Scan every 5 minutes for other Webmin servers
	chroot $1 perl -pi -e "s/(\{\'notfound\'\}\+\+ >=) 3/\$1 1/;" /usr/share/webmin/servers/auto.pl
	chroot $1 bash -c 'echo "#!/usr/bin/perl
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

    chroot $1 chmod 755 /etc/webmin/servers/auto.pl
# For now - disable automatic scanning
#	chroot $1 bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /etc/webmin/servers/auto.pl") | crontab'
# Enable auto registering instead
	chroot $1 bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /usr/local/bin/origo-ubuntu.pl") | crontab'
# Disable Webmin referer check
	chroot $1 perl -pi -e "s/referers_none=1/referers_none=0/;" /etc/webmin/config
	chroot $1 bash -c 'echo "webprefix=
referer=1
referers=" >> /etc/webmin/config'
# Change fstab since we are using virtio
	chroot $1 perl -pi -e "s/sda/vda/g;" /etc/fstab
# Install webmin module
# Include all the modules we want installed for this app
	tar cvf $dname.wbm.tar origo --exclude=origo/tabs/*
	tar rvf $dname.wbm.tar origo/tabs/commands origo/tabs/files origo/tabs/security origo/tabs/servers origo/tabs/software origo/tabs/tests
	mv $dname.wbm.tar $dname.wbm
	gzip -f $dname.wbm
	cp -a $dname.wbm.gz $1/tmp/origo.wbm.gz
	chroot $1 bash -c '/usr/share/webmin/install-module.pl /tmp/origo.wbm.gz'
# Kill off webmin, which unfortunately get's started from the chroot, preventing it from being unmounted
	pkill -f webmin

# Simple script to register this server with admin webmin server when webmin starts
# This script is also responsible for mounting nfs-share, copy back data, etc. if upgrading/reinstalling
# started network-interface and started portmap and runlevel [2345]
    cp origo-ubuntu.pl $1/usr/local/bin
    chmod 755 $1/usr/local/bin/origo-ubuntu.pl
    chroot $1 bash -c 'echo "start on (started origo-networking)
task
exec /usr/local/bin/origo-ubuntu.pl" > /etc/init/origo-ubuntu.conf'

# Configure IP address from address passed to VM through BIOS parameter SKU Number
    cp origo-networking.pl $1/usr/local/bin
    chmod 755 $1/usr/local/bin/origo-networking.pl
    chroot $1 bash -c 'echo "start on (starting network-interface or starting network-manager or starting networking)
task
exec /usr/local/bin/origo-networking.pl" > /etc/init/origo-networking.conf'

# Set up SSL access to Webmin on port 10001
    chroot $1 cp /etc/apache2/sites-available/default-ssl /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/<VirtualHost _default_:443>/<VirtualHost _default_:10001>/;' /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/(<\/VirtualHost>)/    ProxyPass \/ http:\/\/127.0.0.1:10000\/\n    ProxyPassReverse \/ http:\/\/127.0.0.1:10000\/\n$1/;' /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/(DocumentRoot \/var\/www)/$1\n        <Location \/>\n            deny from all\n            allow from 127.0.0.1 #origo\n            satisfy any\n        <\/Location>/;' /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/Listen 443/Listen 443\n    Listen 10001/;' /etc/apache2/ports.conf

# Disable ondemand CPU-scaling service
    chroot $1 update-rc.d ondemand disable

# Disable gzip compression in Apache (enable it manually if desired)
    chroot $1 a2dismod deflate

# Enable SSL
    chroot $1 a2enmod ssl
    chroot $1 a2ensite default-ssl
    chroot $1 a2ensite webmin-ssl

# Enable mod_proxy
    chroot $1 a2enmod proxy
    chroot $1 a2enmod proxy_http

# Run netserver under xinetd - this is used by the net test in reference app
    chroot $1 perl -pi -e 's/(smsqp\s+11201\/udp)/$1\nnetperf         12865\/tcp/' /etc/services
    chroot $1 perl -pi -e 's/NETSERVER_ENABLE=YES/NETSERVER_ENABLE=NO/' /etc/default/netperf
    chroot $1 bash -c 'echo "netserver: 10.0.0.0/8" >> /etc/hosts.allow'

# Disable ssh login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
    chroot $1 bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "allow=10.0.0.0/8 127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Set nice color xterm as default
    chroot $1 bash -c 'echo "export TERM=xterm-color" >> /etc/bash.bashrc'

# Make stuff available to elfinder
    chroot $1 ln -s /usr/share/webmin/origo/elfinder/img /usr/share/webmin/origo/
    chroot $1 ln -s /mnt/fuel /usr/share/webmin/origo/elfinder/

# Start local webmin again
	`/etc/init.d/webmin start`;

# If called without parameters, build image
else
    vmbuilder kvm ubuntu -o -v --debug --suite precise --components main,universe,multiverse --arch amd64 --rootsize 81920 --user origo --pass origo --hostname $dname --addpkg libjson-perl --addpkg liburi-encode-perl --addpkg curl --addpkg acpid --addpkg openssh-server --addpkg nfs-common --addpkg dmidecode --addpkg man --addpkg libstring-shellquote-perl --addpkg unzip --addpkg sysbench --addpkg netperf --addpkg xinetd --addpkg php5-imagick --addpkg screen --addpkg iptables --addpkg git --addpkg python-software-properties --addpkg python-vm-builder --tmpfs - --domain origo.io --ip 10.1.1.2 --execscript="./$me"
# Clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm
fi

