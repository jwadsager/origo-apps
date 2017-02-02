#!/bin/bash

echo "Performing post-install operations"

rm -r /var/www/html
mv /var/www/codiad /var/www/html
touch /var/www/html/config.php
chown www-data:www-data -R /var/www/html/

