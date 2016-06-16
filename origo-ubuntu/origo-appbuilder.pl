#!/usr/bin/perl

use JSON;
use ConfigReader::Simple;

my $ofile = shift if $ARGV[0];

unless ($ufile) {
    print "Usage: origo-appbuilder 'origofile'\n";
    exit;
}

my $config = ConfigReader::Simple->new($ofile);

# The version of the app we are building
my $version = $config->get("VERSION") || '1.0';
my $baseimage = $config->get("BASEIMAGE");
my $name = $config->get("NAME");
my $includedir = $config->get("INCLUDEDIR");
my $targetdir = $config->get("TARGETDIR") || '/';

my $dname="$name.origo";

# Load nbd
print `modprobe nbd max_part=63`;

# Make base image available in fuel
my $json = `curl -k "https://10.0.0.1/steamengine/images/?action=linkmaster&image=$baseimage"`;
my $jobj = from_json($json);
my $linkpath = $jobj->{linkpath};
my $basepath = $jobj->{path};
while (!(-e $basepath)) {
  print "Waiting for $baseimage...\n";
  sleep 1
}

# Clone base image
print `qemu-img create -f qcow2 -b "$basepath" "$dname.master.qcow2"`;

# Wait for nbd0 to be created
print `qemu-nbd -c /dev/nbd0 "$dname.master.qcow2"`;
while (!(-e "/dev/nbd0p1")) {
  print "Waiting for nbd0p1...\n";
  sleep 1
}

# Mount image
print `mkdir $dname`;
print `mount /dev/nbd0p1 $dname`;

# Copy files
if ($includedir && -e $includedir) {
    print "Copying files...\n";
    print `tar rvf /tmp/$dname.tar $includedir`;
    print `tar xf /tmp/$dname.tar -C $targetdir`;
}

# Unmount base image and clean up
print `umount $dname`;
print `killall qemu-nbd`;
print `rm -d $dname`;
print `rm /tmp/$dname.tar`;
