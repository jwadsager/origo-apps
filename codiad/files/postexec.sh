#!/bin/bash

# This script is executed in the image chroot
echo "Performing post-install operations"

rm -r /var/www/html
mv /var/www/codiad /var/www/html
mv /tmp/files/config.php /var/www/html/
echo '<?php/*|[{"username":"origo","password":"","project":"My Project"}]|*/?>' > /var/www/html/data/users.php
echo '<?php/*|[{"name":"My Project","path":"MyProject"}]|*/?>' > /var/www/html/data/projects.php
echo '<?php/*|[""]|*/?>' > /var/www/html/data/active.php
echo '<?php/*|{"c":"c_cpp","coffee":"coffee","cpp":"c_cpp","css":"css","d":"d","erb":"html_ruby","h":"c_cpp","hpp":"c_cpp","htm":"html","html":"html","jade":"jade","java":"java","js":"javascript","json":"json","less":"less","md":"markdown","php":"php","php4":"php","php5":"php","phtml":"php","py":"python","rb":"ruby","sass":"scss","scss":"scss","sql":"sql","tpl":"html","vm":"velocity","xml":"xml","pl":"perl","cgi":"perl"}|*/?>' > /var/www/html/data/extensions.php

mkdir "/var/www/html/workspace/MyProject"
# Install some plugins
cd /var/www/html/plugins
git clone https://github.com/Andr3as/Codiad-Permissions
git clone https://github.com/daeks/Codiad-Together
git clone https://github.com/Andr3as/Codiad-Beautify
git clone https://github.com/Andr3as/Codiad-CodeTransfer
git clone https://github.com/Andr3as/Codiad-CodeGit
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
