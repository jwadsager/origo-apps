#!/bin/bash

version="1.0"
dname="origo-reference-xenial"
me=`basename $0`

# change working directory to script's directory
cd ${0%/*}

# if we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"

# stop local webmin
	if [ -e "/etc/init.d/webmin" ]
    	then
        	/etc/init.d/webmin stop
    	fi

	# setup networking
	cp /dev/null $1/etc/network/interfaces
	cp origo-networking.service $1/etc/systemd/system/
	chmod 664 $1/etc/systemd/system/origo-networking.service
	chroot $1 systemctl daemon-reload
	chroot $1 systemctl enable origo-networking.service

	# install webmin
	chroot $1 apt-get -q -y install perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python
	wget http://prdownloads.sourceforge.net/webadmin/webmin_1.791_all.deb -O $1/webmin_1.791_all.deb
	chroot $1 dpkg --install /webmin_1.791_all.deb

	chroot $1 perl -pi -e 's/Listen 443/Listen 443\n    Listen 10001/;' /etc/apache2/ports.conf
        chroot $1 a2dissite 000-default
        chroot $1 a2dissite default-ssl
        chroot $1 a2enmod proxy
        chroot $1 a2enmod proxy_http
        chroot $1 a2enmod ssl
        cp Apache/webmin-ssl.conf $1/etc/apache2/sites-enabled/webmin-ssl.conf

# Set up automatic scanning for other Webmin servers
	chroot $1 bash -c 'echo "auto_pass=origo
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
# Allow unauthenticated access to wordpress module "origo" as user "origo"
	chroot $1 bash -c 'echo "anonymous=/origo=origo" >> /etc/webmin/miniserv.conf'
# Disable Webmin SSL
	chroot $1 perl -pi -e "s/ssl=1/ssl=0/g;" /etc/webmin/miniserv.conf
# Scan every 5 minutes for other Webmin servers
	chroot $1 perl -pi -e "s/(\{\'notfound\'\}\+\+ >=) 3/\$1 0/;" /usr/share/webmin/servers/auto.pl
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
# First exclude all, then include all the modules we want installed for this app
	tar cvf $dname.wbm.tar origo --exclude=origo/tabs/*
	tar rvf $dname.wbm.tar origo/tabs/security origo/tabs/software origo/tabs/servers
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
    cp origo-trusty-networking.pl $1/usr/local/bin/origo-networking.pl
    chmod 755 $1/usr/local/bin/origo-networking.pl
    chroot $1 bash -c 'echo "start on starting network-interface
instance ens3
task
exec /usr/local/bin/origo-networking.pl" > /etc/init/origo-networking.conf'

# Disable ondemand CPU-scaling service
    chroot $1 update-rc.d ondemand disable

# Disable gzip compression in Apache (enable it manually if desired)
    chroot $1 a2dismod deflate

# Disable ssh login - reenable from configuration UI
   chroot $1 bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
   chroot $1 bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
   chroot $1 bash -c 'echo "allow=10.0.0.0/8 127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Set nice color xterm as default
    chroot $1 bash -c 'echo "export TERM=xterm-color" >> /etc/bash.bashrc'
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /home/origo/.bashrc
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /root/.bashrc

# Start local webmin again
    if [ -e "/etc/init.d/webmin" ]; then
        /etc/init.d/webmin start
    fi

# If called without parameters, build image, sizes 9216, 81920, 10240
else
	vmbuilder kvm ubuntu \
		-o -v --debug \
		--suite xenial \
		--arch amd64 \
		--rootsize 9216 \
		--user origo --pass origo \
		--hostname $dname \
		--addpkg linux-image-generic \
		--addpkg libjson-perl \
		--addpkg liburi-encode-perl \
		--addpkg curl \
		--addpkg acpid \
		--addpkg openssh-server \
		--addpkg python-vm-builder \
		--addpkg memcached \
		--addpkg nfs-common \
		--addpkg dmidecode \
		--addpkg unzip \
		--addpkg apache2 \
		--addpkg libstring-shellquote-perl \
		--addpkg git \
		--domain origo.io \
		--ip 10.1.1.2 \
		--execscript="./$me"

	# clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm

	# convert to qcow2
	qemu-img amend -f qcow2 -o compat=0.10 ./$dname-$version.master.qcow2
fi

