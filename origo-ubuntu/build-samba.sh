#!/bin/bash

# The version of the app we are building
version="1.0"
#dname=`basename "$PWD"`
dname="origo-samba"
me=`basename $0`

# Change working directory to script's directory
cd ${0%/*}

## If we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"
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
	chroot $1 bash -c 'echo "/dev/vdb   /mnt/data ext4    noatime,user_xattr,acl 0   0" >> /etc/fstab'
# Install webmin module
# First exclude all, then include all the modules we want installed for this app
	tar cvf $dname.wbm.tar origo --exclude=origo/tabs/*
	tar rvf $dname.wbm.tar origo/tabs/groups origo/tabs/samba origo/tabs/security origo/tabs/software origo/tabs/users
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
    chroot $1 bash -c 'echo "start on (started origo-samba-networking)
task
exec /usr/local/bin/origo-ubuntu.pl" > /etc/init/origo-ubuntu.conf'

# Configure IP address from address passed to VM through BIOS parameter SKU Number
    cp origo-samba-networking.pl $1/usr/local/bin
    chmod 755 $1/usr/local/bin/origo-samba-networking.pl
    chroot $1 bash -c 'echo "start on (starting network-interface or starting network-manager or starting networking)
task
exec /usr/local/bin/origo-samba-networking.pl" > /etc/init/origo-samba-networking.conf'

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

# Run netserver under xinetd
    chroot $1 perl -pi -e 's/(smsqp\s+11201\/udp)/$1\nnetperf         12865\/tcp/' /etc/services
    chroot $1 perl -pi -e 's/NETSERVER_ENABLE=YES/NETSERVER_ENABLE=NO' /etc/default/netperf
    chroot $1 bash -c 'echo "netserver: 10.0.0.0/8" >> /etc/hosts.allow'

# Disable ssh login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
    chroot $1 bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "allow:10.0.0.0/8  127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Add Samba4 repo
    chroot $1 add-apt-repository "deb http://ppa.launchpad.net/kernevil/samba-4.0/ubuntu precise main"
    chroot $1 apt-get update
    chroot $1 apt-get -q -y --force-yes install samba4

# Install auth_tkt repo
    chroot $1 add-apt-repository "ppa:wiktel/ppa"
    chroot $1 apt-get update
    chroot $1 apt-get -q -y --force-yes install libapache2-mod-auth-tkt-prefork

	chroot $1 bash -c 'echo "TKTAuthSecret \"AjyxgfFJ69234u\"
TKTAuthDigestType SHA512
SetEnv MOD_AUTH_TKT_CONF \"/etc/apache2/conf.d/auth_tkt.conf\"
<Directory /var/www/auth>
  Order deny,allow
  Allow from all
  Options -Indexes
  <FilesMatch \"\.cgi\$\">
    SetHandler perl-script
    PerlResponseHandler ModPerl::Registry
    PerlOptions +ParseHeaders
    Options +ExecCGI
  </FilesMatch>
  <FilesMatch \"\.pm\$\">
    Deny from all
  </FilesMatch>
</Directory>
<LocationMatch \"(php|/elfinder/index\.cgi)\">
    order deny,allow
    AuthName Services
    AuthType None
    TKTAuthLoginURL /auth/login.cgi
    TKTAuthIgnoreIP on
    deny from all
    require valid-user
    Satisfy any
  <ifModule mod_headers.c>
     Header unset ETag
     Header set Cache-Control \"max-age=0, no-cache, no-store, must-revalidate\"
     Header set Pragma \"no-cache\"
     Header set Expires \"Wed, 11 Jan 1984 05:00:00 GMT\"
  </ifModule>
</LocationMatch>
<Location /origo/elfinder/>
    ProxyPass http://127.0.0.1:10000/origo/elfinder/
    ProxyPassReverse http://127.0.0.1:10000/origo/elfinder/
</Location>
<LocationMatch \"(^/users/|^/shared/|^/groups/)\">
    order deny,allow
    Satisfy all
    AuthType None
    TKTAuthLoginURL /auth/login.cgi
    TKTAuthIgnoreIP on
    require valid-user
    RewriteEngine On
    ## Prevent redirect loop
    RewriteCond %{ENV:REDIRECT_STATUS} ^\$
    RewriteRule users/[^\/]+(.*) /users/%{REMOTE_USER}\$1
    ## Require presence of file named \".groupaccess_user\" for each user in group who should have access
    SetEnvIf Request_URI \"^/groups/([^\/]+)/\" PATH_GROUP=\$1
    RewriteCond %{REQUEST_URI} ^\/groups\/
    RewriteCond \"/mnt/data/groups/%{ENV:PATH_GROUP}/.groupaccess_%{REMOTE_USER}\" !-f
    RewriteRule ^.*\$ - [E=NO_ACCESS:%{ENV:PATH_GROUP},G]
    Header set No_Access %{NO_ACCESS}e
</LocationMatch>
<LocationMatch \"auth_tkt=/\">
    TKTAuthTimeout 48h
</LocationMatch>
<Location \"/shared/\">
    AuthType None
    TKTAuthLoginURL auth/login.cgi
    TKTAuthIgnoreIP on
    require valid-user
# Disallow guest user 'g' access to shared - all other users have access
    RewriteEngine On
    RewriteCond %{REMOTE_USER} ^g$
    RewriteRule ^.*$ - [G]
</Location>
" > /etc/apache2/conf.d/auth_tkt.conf'

# Configure Samba
    chroot $1 samba-tool domain provision --realm=origo.lan --domain=origo --host-name=$dname --dnspass="Passw0rd" --adminpass="Passw0rd" --server-role=dc --dns-backend=SAMBA_INTERNAL --use-rfc2307 --use-xattrs=yes

    chroot $1 perl -pi -e 's/(\[global\])/$1\n   root preexec = \/bin\/mkdir \/mnt\/data\/users\/%U\n   dns forwarder = 10.0.0.1\n   log level = 2\n   log file = \/var\/log\/samba\/samba.log.%m\n   max log size = 50\n   debug timestamp = yes\n   idmap_ldb:use rfc2307 = yes\n   veto files = \/.groupaccess_*\/.tmb\/.quarantine\//' /etc/samba/smb.conf
    chroot $1 perl -pi -e 's/(\[netlogon\])/$1\n   browseable = no/' /etc/samba/smb.conf
    chroot $1 perl -pi -e 's/(\[sysvol\])/$1\n   browseable = no/' /etc/samba/smb.conf
    chroot $1 bash -c 'echo "
[home]
   path = /mnt/data/users/%U
   read only = no
   browseable = yes
   hide dot files = yes
   hide unreadable = yes
   valid users = %U
   create mode = 0660
   directory mode = 0770
   inherit acls = Yes
   veto files = /aquota.user/lost+found/

[shared]
   path = /mnt/data/shared
   read only = no
   browseable = yes
   hide dot files = yes
   hide unreadable = yes
   create mode = 0660
   directory mode = 0770
   inherit acls = Yes

include = /etc/samba/smb.conf.groups

" >> /etc/samba/smb.conf'
    touch $1/etc/samba/smb.conf.groups

# Make everything related to elfinder available through elfinder dir
    chroot $1 ln -s /usr/share/webmin/origo/bootstrap /usr/share/webmin/origo/elfinder/bootstrap
    chroot $1 ln -s /usr/share/webmin/origo/strength /usr/share/webmin/origo/elfinder/strength
    chroot $1 ln -s /usr/share/webmin/origo/css/flat-ui.css /usr/share/webmin/origo/elfinder/css/flat-ui.css
    chroot $1 ln -s /usr/share/webmin/origo/images/origo-gray.png /usr/share/webmin/origo/elfinder/img/origo-gray.png

# Finish configuring Apache
    cp ticketmaster.pl $1/usr/local/bin
    chmod 755 $1/usr/local/bin/ticketmaster.pl
    mkdir $1/etc/perl/Apache
    cp Apache/AuthTkt.pm $1/etc/perl/Apache

    mkdir $1/var/www/auth
    gunzip $1/usr/share/doc/libapache2-mod-auth-tkt-prefork/cgi/login.cgi.gz
    gunzip $1/usr/share/doc/libapache2-mod-auth-tkt-prefork/cgi/Apache/AuthTkt.pm.gz
    cp -a $1/usr/share/doc/libapache2-mod-auth-tkt-prefork/cgi/* $1/var/www/auth
    cp auth-login.cgi $1/var/www/auth/login.cgi
    chmod 755 $1/var/www/auth/*
    cp AuthTktConfig.pm $1/var/www/auth/

    chroot $1 /usr/sbin/a2enmod rewrite
    chroot $1 /usr/sbin/a2enmod headers

#    chroot $1 mkdir /mnt/data/users
#    chroot $1 mkdir /mnt/data/users/administrator
#    chroot $1 mkdir /mnt/data/shared
#    chroot $1 mkdir /mnt/data/groups
    chroot $1 rm -r /usr/share/webmin/origo/files

    chroot $1 ln -s /mnt/data/shared /var/www/shared
    chroot $1 ln -s /mnt/data/users /var/www/users
    chroot $1 ln -s /mnt/data/groups /var/www/groups

    chroot $1 ln -sf /opt/samba4/private/krb5.conf /etc/krb5.conf

# Set up btsync
    chroot $1 bash -c 'echo "start on started networking
expect fork
respawn
exec /usr/share/webmin/origo/tabs/samba/bittorrent_sync_x64/btsync --nodaemon --config /usr/share/webmin/origo/tabs/samba/bittorrent_sync_x64/btconfig.json &" > /etc/init/origo-btsync.conf'

# If called without parameters, build image
else
vmbuilder kvm ubuntu -o -v --debug --suite precise --components main,universe,multiverse --arch amd64 --rootsize 81920 --user origo --pass origo --hostname $dname --addpkg libjson-perl --addpkg liburi-encode-perl --addpkg curl --addpkg acpid --addpkg openssh-server --addpkg nfs-common --addpkg dmidecode --addpkg man --addpkg unzip --addpkg python-software-properties --addpkg php5-imagick --addpkg heimdal-clients --addpkg libauthen-simple-ldap-perl --addpkg libstring-shellquote-perl --addpkg libapache2-mod-perl2 --tmpfs - --domain origo.io --ip 10.1.1.2 --execscript="./$me"
# --mirror=http://us-east-1.ec2.archive.ubuntu.com/ubuntu
# Clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm
# Create data image
    [ -f ./samba/users ] || mkdir -p ./samba/users/administrator ./samba/groups ./samba/shared
    [ -f ./$dname-$version-data.master.qcow2 ] || virt-make-fs --format=qcow2 --type=ext4 --size=100G samba "./$dname-$version-data.master.qcow2"
fi

