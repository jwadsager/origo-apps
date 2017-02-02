#!/bin/bash

echo "Performing post-install operations"

touch /var/www/html/config.php
chown www-data:www-data -R /var/www/html/

