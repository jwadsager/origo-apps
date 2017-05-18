#!/usr/bin/perl

unless (-e '/etc/piwik.seeded') {
    my $hostname = `hostname`;
    my $email = `curl -k --silent https://10.0.0.1/steamengine/users/me/username`;
    print `mysql -e "create database piwik"`;
    print `mysql -e "CREATE USER piwik@localhost"`;
    print `mysql -e "GRANT ALL PRIVILEGES ON piwik.* TO 'piwik'@'localhost';"`;
    print `mysql -e "FLUSH PRIVILEGES;"`;
    `touch /etc/piwik.seeded`;
}
