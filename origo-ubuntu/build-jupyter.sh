#!/bin/bash

version="beta10"
dname="origo-jupyter"
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

	chroot $1 bash -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list'
	chroot $1 wget http://www.webmin.com/jcameron-key.asc
	chroot $1 apt-key add jcameron-key.asc
	chroot $1 apt-get update
	chroot $1 apt-get  -q -y --force-yes install apache2-mpm-prefork libapache2-mod-php5
	chroot $1 apt-get  -q -y --force-yes install webmin

	chroot $1 apt-get -q -y remove apache2*
	chroot $1 apt-get -q -y purge apache2*
	chroot $1 add-apt-repository -y ppa:ondrej/php5
	chroot $1 apt-get update
	chroot $1 apt-get -q -y install apache2
	chroot $1 a2enmod proxy_wstunnel
	chroot $1 a2enmod rewrite
	
    	chroot $1 perl -pi -e 's/Listen 443/Listen 443\n    Listen 10001/;' /etc/apache2/ports.conf
	chroot $1 a2dissite 000-default 
	chroot $1 a2dissite default-ssl
    	chroot $1 a2enmod proxy
    	chroot $1 a2enmod proxy_http
    	chroot $1 a2enmod ssl
   	cp Apache/webmin-ssl.conf $1/etc/apache2/sites-enabled/webmin-ssl.conf
	cp jupyter/vhost $1/etc/apache2/sites-enabled/jupyterhub.conf
	chroot $1 service apache2 restart

	chroot $1 wget -q https://3230d63b5fc54e62148e-c95ac804525aac4b6dba79b00b39d1d3.ssl.cf1.rackcdn.com/Anaconda3-4.0.0-Linux-x86_64.sh -O /anaconda.sh
	chroot $1 sed -e '/unset LD_LIBRARY_PATH/s/^/#/g' -i /anaconda.sh
	chroot $1 sed -e '/verify the size of the installer/,+5 s/^/#/g' -i /anaconda.sh
	
	# install python
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 bash /anaconda.sh -f -b -p /anaconda

	# kernels
	# TODO: Add julialang and R
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 /anaconda/bin/conda create --yes -n py3 python=3 anaconda
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 /anaconda/bin/conda create --yes -n py2 python=2 anaconda
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 bash -c 'source /anaconda/bin/activate py3;ipython kernel install'
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib:/anaconda/pkgs/python-2.7.11-0/lib' PATH=/anaconda/bin:$PATH chroot $1 bash -c 'source /anaconda/bin/activate py2;ipython kernel install'

	# jupyterhub deps
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 bash -c 'source /anaconda/bin/activate py3;/anaconda/bin/conda install --yes python=3 sqlalchemy tornado jinja2 traitlets requests pip'
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/bin:$PATH chroot $1 bash -c 'source /anaconda/bin/activate py3;/anaconda/bin/pip install --upgrade pip'
	chroot $1 wget -q https://deb.nodesource.com/setup_0.12 -O /node.sh
	chroot $1 bash /node.sh
	chroot $1 apt-get -q -y install nodejs build-essential
	chroot $1 npm install -g configurable-http-proxy

	# install jupyterhub itself
	LD_LIBRARY_PATH='/anaconda/pkgs/python-3.5.1-0/lib' PATH=/anaconda/envs/py3/bin:$PATH chroot $1 bash -c 'source /anaconda/bin/activate py3; pip install --upgrade --ignore-installed jupyterhub'
	cp ./jupyter/jupyterhub_config.py $1/

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
	#tar rvf $dname.wbm.tar origo/tabs/security origo/tabs/software origo/tabs/wordpress
	tar rvf $dname.wbm.tar origo/tabs/security origo/tabs/software origo/tabs/servers origo/tabs/jupyter
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
    chroot $1 bash -c 'echo "start on starting network-interface
instance eth0
task
exec /usr/local/bin/origo-networking.pl" > /etc/init/origo-networking.conf'

# Utility script for setting up WordPress to work with this app
    cp jupyter/jupyterhub.sh $1/etc/init.d/jupyterhub
    chmod +x $1/etc/init.d/jupyterhub
    chroot $1 update-rc.d jupyterhub defaults
    #chroot $1 bash -c 'echo "start on (started origo-networking)
#task
#exec /etc/init.d/jupyterhub start" > /etc/init/jupyterhub.conf'


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
		--suite precise \
		--mirror http://archive.ubuntu.com/ubuntu \
		--arch amd64 --rootsize 9216 \
		--user origo --pass origo \
		--hostname $dname \
		--addpkg libjson-perl \
		--addpkg liburi-encode-perl \
		--addpkg curl \
		--addpkg acpid \
		--addpkg openssh-server \
		--addpkg memcached \
		--addpkg php5-memcache \
		--addpkg nfs-common \
		--addpkg dmidecode \
		--addpkg unzip \
		--addpkg default-jdk \
		--addpkg mysql-server \
		--addpkg libstring-shellquote-perl \
		--addpkg python-software-properties \
		--tmpfs - --domain origo.io --ip 10.1.1.2 --execscript="./$me"
# Clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm
fi

