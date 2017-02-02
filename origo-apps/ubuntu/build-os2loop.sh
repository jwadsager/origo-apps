#!/bin/bash

version="alpha-`date +%Y_%m_%d_%H_%M_%S`"
dname="os2loop"
me=`basename $0`

php_version="5.5"

# change working directory to script's directory
cd ${0%/*}

# if we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"
# stop local webmin from blocking port 10000
	if [ -e "/etc/init.d/webmin" ]
    	then
        	/etc/init.d/webmin stop
    	fi

# install webmin
	chroot $1 bash -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list'
	chroot $1 wget http://www.webmin.com/jcameron-key.asc
	chroot $1 apt-key add jcameron-key.asc
	chroot $1 apt-get update
	chroot $1 apt-get -q -y --force-yes install webmin
# Install IOzone
	chroot $1 apt-get  -q -y --force-yes install iozone3
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
# First exclude all, then include all the modules we want installed for this app
	tar cvf $dname.wbm.tar origo --exclude=origo/tabs/*
	tar rvf $dname.wbm.tar origo/tabs/security origo/tabs/servers origo/tabs/os2loop
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
    ln -s $1/usr/local/bin/origo-ubuntu.pl /usr/local/bin/origo-helper
    chroot $1 bash -c 'echo "start on (started origo-networking)
task
exec /usr/local/bin/origo-ubuntu.pl" > /etc/init/origo-ubuntu.conf'

# Configure IP address from address passed to VM through BIOS parameter SKU Number
    cp origo-xenial-networking.pl $1/usr/local/bin/origo-networking.pl
    chmod 755 $1/usr/local/bin/origo-networking.pl
	> $1/etc/network/interfaces
    chroot $1 bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Setup network for Origo Compute
Before=network-pre.target
Wants=network-pre.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/origo-networking.pl
TimeoutSec=0
RemainAfterExit=yes
[Install]
WantedBy=network.target" > /etc/systemd/system/origo-networking.service'
	chmod 664 $1/etc/systemd/system/origo-networking.service
	chroot $1 systemctl daemon-reload
	chroot $1 systemctl enable origo-networking.service

# Set up SSL access to Webmin on port 10001
    chroot $1 cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/<VirtualHost _default_:443>/<VirtualHost _default_:10001>/;' /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/(<\/VirtualHost>)/    ProxyPass \/ http:\/\/127.0.0.1:10000\/\n            ProxyPassReverse \/ http:\/\/127.0.0.1:10000\/\n$1/;' /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/(DocumentRoot \/var\/www\/html)/$1\n        <Location \/>\n            deny from all\n            allow from 10.0.0.0\/8 #origo\n        <\/Location>/;' /etc/apache2/sites-available/webmin-ssl.conf
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

# Disable ssh login - reenable from configuration UI
   chroot $1 bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
   chroot $1 bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
   chroot $1 bash -c 'echo "allow=10.0.0.0/8 127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Set nice color xterm as default
    chroot $1 bash -c 'echo "export TERM=xterm-color" >> /etc/bash.bashrc'
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /home/origo/.bashrc
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /root/.bashrc

# Make stuff available to elfinder
    chroot $1 ln -s /usr/share/webmin/origo/elfinder/img /usr/share/webmin/origo/
    chroot $1 ln -s /mnt/fuel /usr/share/webmin/origo/elfinder/
    chroot $1 mkdir /usr/share/webmin/origo/files

# Start local webmin again
    if [ -e "/etc/init.d/webmin" ]; then
        /etc/init.d/webmin start
    fi

    # configure php
    chroot $1 update-alternatives --set php /usr/bin/php${php_version}
    chroot $1 bash -c 'sed -i "/memory_limit = 128M/c memory_limit = 256M" /etc/php/5.5/apache2/php.ini'
    chroot $1 bash -c 'sed -i "/;date.timezone =/c date.timezone = Europe\/Copenhagen" /etc/php/5.5/apache2/php.ini'
    chroot $1 bash -c 'sed -i "/;date.timezone =/c date.timezone = Europe\/Copenhagen" /etc/php/5.5/cli/php.ini'
    chroot $1 bash -c 'sed -i "/upload_max_filesize = 2M/c upload_max_filesize = 16M" /etc/php/5.5/apache2/php.ini'
    chroot $1 bash -c 'sed -i "/post_max_size = 8M/c post_max_size = 20M" /etc/php/5.5/apache2/php.ini'
    chroot $1 bash -c 'sed -i "/;realpath_cache_size = 16k/c realpath_cache_size = 256k" /etc/php/5.5/apache2/php.ini'
    chroot $1 pecl install uploadprogress
    chroot $1 bash -c 'echo "extension=uploadprogress.so" >> /etc/php/5.5/apache2/php.ini'

    chroot $1 bash -c 'cat > /etc/php/5.5/mods-available/apc.ini <<DELIM
apc.enabled=1
apc.shm_segments=1
apc.optimization=0
apc.shm_size=64M
apc.ttl=7200
apc.user_ttl=7200
apc.num_files_hint=1024
apc.mmap_file_mask=/tmp/apc.XXXXXX
apc.enable_cli=0
apc.cache_by_default=1
DELIM'


    # configure varnish
    # workaround for varnish on xenial, put in /etc/default/varnish when fixed by varnish/ubuntu
    chroot $1 bash -c 'cat > /lib/systemd/system/varnish.service <<DELIM
[Unit]
Description=Varnish HTTP accelerator
Documentation=https://www.varnish-cache.org/docs/4.1/ man:varnishd

[Service]
Type=simple
LimitNOFILE=131072
LimitMEMLOCK=82000
ExecStart=/usr/sbin/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f /etc/varnish/default.vcl -S /etc/varnish/secret -s malloc,256m
ExecReload=/usr/share/varnish/reload-vcl
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
DELIM'

    chroot $1 bash -c 'cat > /etc/varnish/default.vcl <<DELIM
vcl 4.0;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}
DELIM'

    # configure apache
    chroot $1 bash -c 'cat > /etc/apache2/ports.conf <<DELIM
Listen 8080

<IfModule ssl_module>
        Listen 443
        Listen 10001
</IfModule>

<IfModule mod_gnutls.c>
        Listen 443
        Listen 10001
</IfModule>
DELIM'
    chroot $1 rm -rf /etc/apache2/sites-enabled/{000-default.conf,default-ssl.conf}
    chroot $1 bash -c 'cat > /etc/apache2/sites-available/os2loop.conf <<DELIM
<VirtualHost *:8080>
    ServerName OS2Loop
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
    </Directory>
</VirtualHost>
DELIM'
    cp Apache/webmin-ssl.conf $1/etc/apache2/sites-available
    chroot $1 a2ensite os2loop webmin-ssl
    chroot $1 a2enmod php${php_version}

    # install composer
    chroot $1 php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    chroot $1 php -r "if (hash_file('SHA384', 'composer-setup.php') === '92102166af5abdb03f49ce52a40591073a7b859a86e8ff13338cf7db58a19f7844fbc0bb79b2773bf30791e935dbd938') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
    chroot $1 php composer-setup.php
    chroot $1 php -r "unlink('composer-setup.php');"
    chroot $1 mv composer.phar /usr/local/bin/composer

    # install drush
    chroot $1 mkdir --parents /opt/drush-6.1.0
    chroot $1 cd /opt/drush-6.1.0
    chroot $1 composer init --require=drush/drush:6.1.0 -n
    chroot $1 composer config bin-dir /usr/local/bin
    chroot $1 composer install

    # install drupal profile
    chroot $1 rm -rf /var/www/html
    chroot $1 drush make --no-cache https://raw.github.com/os2loop/profile/master/drupal.make /var/www/html
    chroot $1 chown -R www-data:www-data /var/www/html

    # setup tomcat and solr
    chroot $1 sed --in-place '/\<Connector port="8080" protocol="HTTP\/1.1"/c \<Connector port="8983" protocol="HTTP\/1.1"' /var/lib/tomcat7/conf/server.xml
    chroot $1 sed --in-place 's@.*JAVA_HOME.*@JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64@' /etc/default/tomcat7
    chroot $1 wget https://archive.apache.org/dist/lucene/solr/4.9.1/solr-4.9.1.tgz -O /solr.tgz
    chroot $1 tar xzf /solr.tgz -C /
    chroot $1 rm /solr.tgz
    chroot $1 cp /solr-*/example/lib/ext/* /usr/share/tomcat7/lib/
    chroot $1 cp /solr-*/dist/solr-*.war /var/lib/tomcat7/webapps/solr.war
    chroot $1 cp -R /solr-*/example/solr /var/lib/tomcat7
    chroot $1 rm -rf /solr-*
    chroot $1 chown -R tomcat7:tomcat7 /var/lib/tomcat7/solr

    # add solr core
    chroot $1 cp -r /var/lib/tomcat7/solr/collection1 /var/lib/tomcat7/solr/loop
    chroot $1 bash -c 'sed -i "s/collection1/loop/" /var/lib/tomcat7/solr/loop/core.properties'
    chroot $1 bash -c 'cd / && drush dl search_api_solr'
    chroot $1 bash -c 'cp /search_api_solr/solr-conf/4.x/* /var/lib/tomcat7/solr/loop/conf/'
    chroot $1 rm -rf /search_api_solr
    chroot $1 chown -R tomcat7:tomcat7 /var/lib/tomcat7/solr

# if called without parameters, build image, sizes 9216, 81920, 10240
else
	vmbuilder kvm ubuntu -o -v \
		--debug \
		--suite xenial \
		--arch amd64 \
		--components main,universe,multiverse \
		--rootsize 81920 \
		--user origo --pass origo \
		--hostname $dname \
		--domain origo.io \
		--ip 10.1.1.2 \
		--execscript="./$me" \
		--mirror http://mirror.easyspeedy.com/ubuntu/ \
		--ppa ondrej/php \
		--ppa ondrej/mysql-5.6 \
		--addpkg acpid \
		--addpkg apache2 \
		--addpkg apt-show-versions \
		--addpkg curl \
		--addpkg dmidecode \
		--addpkg git \
		--addpkg iptables \
		--addpkg libapache2-mod-php${php_version} \
		--addpkg libauthen-pam-perl \
		--addpkg libio-pty-perl \
		--addpkg libjson-perl \
		--addpkg libpam-runtime \
		--addpkg liburi-encode-perl \
		--addpkg libstring-shellquote-perl \
		--addpkg libnet-ssleay-perl \
		--addpkg linux-image-generic \
		--addpkg memcached \
		--addpkg mysql-server-5.6 \
		--addpkg nfs-common \
		--addpkg openjdk-8-jre \
		--addpkg openssh-server \
		--addpkg openssl \
		--addpkg php-pear \
		--addpkg php${php_version}-apc \
		--addpkg php${php_version}-curl \
		--addpkg php${php_version}-dev \
		--addpkg php${php_version}-gd \
		--addpkg php${php_version}-imagick \
		--addpkg php${php_version}-mbstring \
		--addpkg php${php_version}-memcached \
		--addpkg php${php_version}-mysql \
		--addpkg php${php_version}-xml \
		--addpkg python \
		--addpkg python-software-properties \
		--addpkg tomcat7 \
		--addpkg unzip \
		--addpkg varnish \
		--addpkg xinetd

	# clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm

	#qemu-img create -f qcow2 $dname-data.qcow2 80G

        # convert to qcow2
        qemu-img amend -f qcow2 -o compat=0.10 ./$dname-$version.master.qcow2
        #qemu-img amend -f qcow2 -o compat=0.10 ./$dname-data.qcow2
fi

