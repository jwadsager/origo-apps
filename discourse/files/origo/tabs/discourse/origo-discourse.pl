#!/usr/lib/perl

unless (-e '/etc/discourse.seeded') {
    my $hostname = `hostname`;
    my $email = `curl -k --silent https://10.0.0.1/steamengine/users/me/username`;
    print `discourse config:set DISCOURSE_DEVELOPER_EMAILS=$email`;
    print `discourse config:set DISCOURSE_HOSTNAME=$hostname`;
    print `discourse run rake db:migrate db:seed_fu`;
    `touch /etc/discourse.seeded`;
}
