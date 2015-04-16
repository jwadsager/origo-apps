#!/bin/bash

if grep --quiet steamengine /usr/share/wordpress/wp-admin/install.php; then
	echo "Modifications already made"
else
# Fix link to install.css
	perl -pi -e 's/(<\?php(\n)?\s+wp_admin_css\(.+install.+ true \);(\n)?\s+\?>)/<link rel="stylesheet" id="install-css"  href="css\/install\.css" type="text\/css" media="all" \/>/;' /usr/share/wordpress/wp-admin/install.php
    perl -pi -e 's/wp_admin_css\(.+install.+ true \);/echo "<link rel=\\"stylesheet\\" id=\\"install-css\\"  href=\\"css\/install\.css\\" type=\\"text\/css\\" media=\\"all\\" \/>"/g;' /usr/share/wordpress/wp-admin/install.php

# Make install page prettier in Steamengine configure dialog
	perl -pi -e 's/margin:2em auto/margin:0 auto/;' /usr/share/wordpress/wp-admin/css/install.css

# Redirect to Webmin when WordPress is installed
	perl -pi -e 's/(<a href="\.\.\/wp-login\.php".+<\/a>)/<!-- $1 --><script>var pipeloc=location\.href\.substring(0,location.href.indexOf("\/home")); location=pipeloc \+ ":10000\/origo\/?wp=<?php echo \$_SERVER[HTTP_HOST]; ?>";<\/script>/;' /usr/share/wordpress/wp-admin/install.php
	perl -pi -e 's/(action="install.php\?step=2)/$1&host=<?php echo \$_SERVER[HTTP_HOST]; ?>/;' /usr/share/wordpress/wp-admin/install.php

# Ask Steamengine to change the managementlink from Wordpress install page, so the above redirect is not needed on subsequent loads
	perl -pi -e 's/(if \( is_blog_installed\(\) \) \{)/$1\n    \`curl -k -X PUT --data-urlencode "PUTDATA={\\"uuid\\":\\"this\\",\\"managementlink\\":\\"\/steamengine\/pipe\/http:\/\/{uuid}:10000\/origo\/\\"}" https:\/\/10.0.0.1\/steamengine\/images\`;/;' /usr/share/wordpress/wp-admin/install.php

# Make strength meter work in install page after upgrading WordPress
	perl -pi -e 's/(.+src.+ => )(empty.+),/$1\"\.\.\/wp-includes\/js\/zxcvbn\.min\.js\"/;' /usr/share/wordpress/wp-includes/script-loader.php
fi
