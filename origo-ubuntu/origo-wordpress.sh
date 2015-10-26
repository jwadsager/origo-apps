#!/bin/bash

if grep --quiet "HTTP_HOST" /usr/share/wordpress/wp-admin/install.php; then
	echo "Modifications already made"
else
	echo "Modifying WordPress files"
# Fix link to install.css
	perl -pi -e 's/(<\?php(\n)?\s+wp_admin_css\(.+install.+ true \);(\n)?\s+\?>)/<link rel="stylesheet" id="install-css"  href="css\/install\.css" type="text\/css" media="all" \/>/;' /usr/share/wordpress/wp-admin/install.php
    perl -pi -e 's/wp_admin_css\(.+install.+ true \);/echo "<link rel=\\"stylesheet\\" id=\\"install-css\\"  href=\\"css\/install\.css\\" type=\\"text\/css\\" media=\\"all\\" \/>";/g;' /usr/share/wordpress/wp-admin/install.php

# Make install page prettier in Steamengine configure dialog
	perl -pi -e 's/margin:2em auto/margin:0 auto/;' /usr/share/wordpress/wp-admin/css/install.css

# Redirect to Webmin when WordPress is installed
#	perl -pi -e 's/(<a href="\.\.\/wp-login\.php".+<\/a>)/<!-- $1 --><script>var pipeloc=location\.href\.substring(0,location.href.indexOf("\/home")); location=pipeloc \+ ":10000\/origo\/?wp=<?php echo \$_SERVER[HTTP_HOST]; ?>";<\/script>/;' /usr/share/wordpress/wp-admin/install.php

# Redirect to Webmin when WordPress is installed
# We need to to a bit of gymnastics because of problems with escaping quotes

# Replace button with link to login page with redirect to our app page
    perl -pi -e 's/(<a href="\.\.\/wp-login\.php".+<\/a>)/<!-- $1 --><script>var pipeloc=location\.href\.substring(0,location.href.indexOf("\/home")); location=pipeloc \+ ":10000\/origo\/?show=showdummy-site";<\/script>/;' /usr/share/wordpress/wp-admin/install.php

    perl -pi -e "unless (\$match) {\$match = s/showdummy/' . \\\$showsite . '/;}" /usr/share/wordpress/wp-admin/install.php
    perl -pi -e 'if (!$match) {$match = s/showdummy/<?php echo \$showsite; ?>/;}' /usr/share/wordpress/wp-admin/install.php

    perl -pi -e 's/(\/\/ Sanity check\.)/$1\n\$showsite=( (strpos(\$_SERVER[HTTP_HOST], ".origo.io")===FALSE)? "default" : substr(\$_SERVER[HTTP_HOST], 0, strpos(\$_SERVER[HTTP_HOST], ".origo.io")) );\n/' /usr/share/wordpress/wp-admin/install.php

# Make link to virtual host work, even if not registered in DNS, by adding host=, which is interpreted by Steamengine proxy
    perl -pi -e "s/(step=1)/\$1\&host=' . \\\$_SERVER[HTTP_HOST] .'/;" /usr/share/wordpress/wp-admin/install.php
	perl -pi -e 's/(action="install.php\?step=2)/$1&host=<?php echo \$_SERVER[HTTP_HOST]; ?>/;' /usr/share/wordpress/wp-admin/install.php

# Ask Steamengine to change the managementlink from Wordpress install page, so the above redirect is not needed on subsequent loads
	perl -pi -e 's/(if \( is_blog_installed\(\) \) \{)/$1\n    \`curl -k -X PUT --data-urlencode "PUTDATA={\\"uuid\\":\\"this\\",\\"managementlink\\":\\"\/steamengine\/pipe\/http:\/\/{uuid}:10000\/origo\/\\"}" https:\/\/10.0.0.1\/steamengine\/images\`;/;' /usr/share/wordpress/wp-admin/install.php

#    perl -pi -e 's/(<h1>.+Success!.+<\/h1>)/$1\n    <?php\n\`curl -k -X PUT --data-urlencode "PUTDATA={\\"uuid\\":\\"this\\",\\"managementlink\\":\\"\/steamengine\/pipe\/http:\/\/{uuid}:10000\/origo\/\\"}" https:\/\/10.0.0.1\/steamengine\/images\`;\n    ?>/;' /usr/share/wordpress/wp-admin/install.php

# Make strength meter work in install page after upgrading WordPress
	perl -pi -e 's/(.+src.+ => )(empty.+),/$1\"\.\.\/wp-includes\/js\/zxcvbn\.min\.js\"/;' /usr/share/wordpress/wp-includes/script-loader.php
fi
