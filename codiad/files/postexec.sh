#!/bin/bash

# This script is executed in the image chroot
echo "Performing post-install operations"

rm -r /var/www/html
mv /var/www/codiad /var/www/html
mv /tmp/files/config.php /var/www/html/
echo '<?php/*|[{"username":"origo","password":"","project":"My Project"}]|*/?>' > /var/www/html/data/users.php
echo '<?php/*|[{"name":"My Project","path":"MyProject"}]|*/?>' > /var/www/html/data/projects.php
echo '<?php/*|[""]|*/?>' > /var/www/html/data/active.php
mkdir "/var/www/html/workspace/MyProject"
chown www-data:www-data -R /var/www/html/
a2enmod cgi
echo 'AddHandler cgi-script cgi pl py
<Directory "/var/www/html">
   Options ExecCGI
</Directory>' >> /etc/apache2/conf-available/serve-cgi-bin.conf

# Add this app's assets to Webmin
mv /tmp/files/origo/tabs/* /usr/share/webmin/origo/tabs/
# Remove "command" tab from Webmin UI
rm -r /usr/share/webmin/origo/tabs/commands
