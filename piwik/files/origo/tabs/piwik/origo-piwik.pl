#!/usr/bin/perl

unless (-e '/etc/piwik.seeded') {
    my $hostname = `hostname`;
    my $email = `curl -k --silent https://10.0.0.1/steamengine/users/me/username`;
    my $externalip = `cat /tmp/externalip`;
    chomp $externalip;
    print `mysql -e "create database piwik;"`;
    print `mysql -e "CREATE USER piwik@localhost;"`;
    print `mysql -e "GRANT ALL PRIVILEGES ON piwik.* TO piwik@localhost;"`;
    print `mysql -e "FLUSH PRIVILEGES;"`;
    print `mysql piwik -e 'INSERT INTO piwik_user (login, superuser_access) VALUES ("origo",1);'`;
    print `perl -pi -e 's/myhost/$externalip/' /var/www/html/piwik/config/config.ini.php`;
    `touch /etc/piwik.seeded`;
}
