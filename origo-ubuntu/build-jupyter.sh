#!/bin/bash

# The version of the app we are building
version="beta5"

dname="origo-jupyter"
me=`basename $0`

# Change working directory to script's directory
cd ${0%/*}

## If we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"
# Stop local webmin from blocking port 10000
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
	chroot $1 apt-get install -y nodejs build-essential
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

# Configure Apache

    chroot $1 bash -c 'echo "<Location />
                ProxyPass http://localhost:8000/
                ProxyPassReverse http://localhost:8000/
        </Location>" >> /etc/apache2/sites-available/default-ssl'



#    chroot $1 bash -c 'echo "Alias /home /usr/share/wordpress
#Alias /home/wp-content /var/lib/wordpress/wp-content
#<Directory /usr/share/wordpress>
#    Options FollowSymLinks
#    AllowOverride Limit Options FileInfo
#    DirectoryIndex index.php
#    Order allow,deny
#    Allow from all
#</Directory>
#<Directory /var/lib/wordpress/wp-content>
#    Options FollowSymLinks
#    Order allow,deny
#    Allow from all
#</Directory>" >> /etc/apache2/sites-available/default'
#
## Configure WordPress
#
#    chroot $1 mkdir /etc/wordpress
#    echo  "<?php
#    define('DB_NAME', 'wordpress_default');
#    define('DB_USER', 'root');
#    define('DB_PASSWORD', '');
#    define('DB_HOST', 'localhost');
#    define('WP_CONTENT_DIR', '/usr/share/wordpress/wp-content');
#    define('WP_CONTENT_URL', '/home/wp-content');
#    define('WP_HOME','/home');
#    define('WP_SITEURL','/home');
#    define('WP_CACHE', true);
#    define('WP_CORE_UPDATE', true);
#?>" >> $1/etc/wordpress/config-default.php
#
# Make homepage redirect to blog
#    chroot $1 bash -c 'echo "<META HTTP-EQUIV=\"Refresh\" Content=\"0; URL=/home/\">" > /var/www/index.html'
#
## Create WordPress database
#    chroot $1 mkdir -p /var/lib/mysql/wordpress_default
#    chroot $1 bash -c 'echo "default-character-set=utf8
#default-collation=utf8_general_ci" > /var/lib/mysql/wordpress_default/db.opt'
#
#    chroot $1 chown -R mysql:mysql /var/lib/mysql/wordpress_default
#
# #Allow theme installation automatic upgrades etc
#    chroot $1 chown -R www-data:www-data /var/lib/wordpress
#    chroot $1 chown -R www-data:www-data /usr/share/wordpress
#    chroot $1 chown -R www-data:www-data /usr/share/javascript/cropper/
#    chroot $1 chown -R www-data:www-data /usr/share/javascript/prototype/
#    chroot $1 chown -R www-data:www-data /usr/share/php
#    chroot $1 chown -R www-data:www-data /usr/share/tinymce
#
## Install newest WordPress
#    echo "Upgrading WordPress to latest version..."
#    cd $1/usr/local/bin; curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
#    chmod 755 $1/usr/local/bin/wp-cli.phar
#    mv $1/usr/local/bin/wp-cli.phar $1/usr/local/bin/wp
#    cd $1/usr/share/wordpress; sudo -u www-data $1/usr/local/bin/wp core download --force
#
# Set up SSL access to Webmin on port 10001
    chroot $1 cp /etc/apache2/sites-available/default-ssl /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/<VirtualHost _default_:443>/<VirtualHost _default_:10001>/;' /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/(<\/VirtualHost>)/    ProxyPass \/ http:\/\/127.0.0.1:10000\/\n    ProxyPassReverse \/ http:\/\/127.0.0.1:10000\/\n$1/;' /etc/apache2/sites-available/webmin-ssl
    chroot $1 perl -pi -e 's/(DocumentRoot \/var\/www)/$1\n        <Location \/>\n            deny from all\n            allow from 10.0.0.0\/8 #origo\n            satisfy any\n        <\/Location>/;' /etc/apache2/sites-available/webmin-ssl
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
    if [ -e "/etc/init.d/webmin" ]
    then
        /etc/init.d/webmin start
    fi

# If called without parameters, build image, sizes 9216, 81920, 10240
else
	vmbuilder kvm ubuntu -o -v --suite precise --arch amd64 --rootsize 9216 --user origo --pass origo --hostname $dname --addpkg libjson-perl --addpkg liburi-encode-perl --addpkg curl --addpkg acpid --addpkg openssh-server --addpkg memcached --addpkg php5-memcache --addpkg nfs-common --addpkg dmidecode --addpkg unzip --addpkg default-jdk --addpkg mysql-server  --addpkg libstring-shellquote-perl --tmpfs - --domain origo.io --ip 10.1.1.2 --execscript="./$me"
# Clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm
fi

