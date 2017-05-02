#!/usr/bin/perl

unless (-e '/etc/discourse.seeded') {
    my $hostname = `hostname`;
    my $email = `curl -k --silent https://10.0.0.1/steamengine/users/me/username`;
    print `echo "CREATE USER \"user\" SUPERUSER PASSWORD 'pass';" | su - postgres -c psql`;
    print `echo "CREATE DATABASE discourse;" | su - postgres -c psql`;
    print `echo "GRANT ALL PRIVILEGES ON DATABASE \"discourse\" TO \"user\";" | su - postgres -c psql`;
    print `discourse config:set DISCOURSE_DEVELOPER_EMAILS=$email`;
    print `discourse config:set DISCOURSE_HOSTNAME=$hostname`;
    print `discourse run rake db:migrate db:seed_fu`;
    `touch /etc/discourse.seeded`;
}
