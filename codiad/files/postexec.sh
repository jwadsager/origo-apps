#!/bin/bash

# This script is executed in the image chroot
echo "Performing post-install operations"

rm -r /var/www/html
mv /var/www/codiad /var/www/html
touch /var/www/html/config.php
chown www-data:www-data -R /var/www/html/

# Add this app's assets to Webmin
mv /tmp/files/origo/tabs/* /usr/share/webmin/origo/tabs/
