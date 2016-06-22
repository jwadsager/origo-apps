#!/bin/bash

echo "Performing post-install operations"

# Simple script to register this server with admin webmin server when webmin starts
# This script is also responsible for mounting nfs-share, copy back data, etc. if upgrading/reinstalling
cp /tmp/files/origo-ubuntu.pl $1/usr/local/bin
chmod 755 /usr/local/bin/origo-ubuntu.pl
ln -s /usr/local/bin/origo-ubuntu.pl /usr/local/bin/origo-helper
bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Utility script for Origo Compute
Wants=network-online.target
After=network.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/origo-ubuntu.pl
TimeoutSec=30
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/origo-ubuntu.service'
chmod 664 /etc/systemd/system/origo-ubuntu.service

# Simple script to configure IP address from address passed to VM through BIOS parameter SKU Number
cp /tmp/files/origo-xenial-networking.pl /usr/local/bin/origo-networking.pl
chmod 755 /usr/local/bin/origo-networking.pl
# Zap existing file
> /etc/network/interfaces
bash -c 'echo "[Unit]
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
chmod 664 /etc/systemd/system/origo-networking.service

systemctl daemon-reload
systemctl enable origo-networking.service
systemctl enable origo-shellinabox.service
systemctl enable origo-ubuntu.service

# Set up SSL access to Webmin on port 10001
cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/webmin-ssl.conf
perl -pi -e 's/<VirtualHost _default_:443>/<VirtualHost _default_:10001>/;' /etc/apache2/sites-available/webmin-ssl.conf
perl -pi -e 's/(<\/VirtualHost>)/    ProxyPass \/ http:\/\/127.0.0.1:10000\/\n            ProxyPassReverse \/ http:\/\/127.0.0.1:10000\/\n$1/;' /etc/apache2/sites-available/webmin-ssl.conf
perl -pi -e 's/(DocumentRoot \/var\/www\/html)/$1\n        <Location \/>\n            deny from all\n            allow from 10.0.0.0\/8 #origo\n        <\/Location>/;' /etc/apache2/sites-available/webmin-ssl.conf
perl -pi -e 's/Listen 443/Listen 443\n    Listen 10001/;' /etc/apache2/ports.conf

# Disable ondemand CPU-scaling service
update-rc.d ondemand disable

# Disable gzip compression in Apache (enable it manually if desired)
a2dismod -f deflate

# Enable SSL
a2enmod ssl
a2ensite default-ssl
a2ensite webmin-ssl

# Enable mod_proxy
a2enmod proxy
a2enmod proxy_http

# Disable ssh login from outside - reenable from configuration UI
bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
bash -c 'echo "allow=10.0.0.0/8 127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Set nice color xterm as default
bash -c 'echo "export TERM=xterm-color" >> /etc/bash.bashrc'
perl -pi -e 's/PS1="/# PS1="/' /home/origo/.bashrc
perl -pi -e 's/PS1="/# PS1="/' /root/.bashrc

