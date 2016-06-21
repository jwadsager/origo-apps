#!/usr/bin/perl

use JSON;
use URI::Escape;
use ConfigReader::Simple;
use Cwd;

my $ofile = shift if $ARGV[0];
my $cwd = cwd();

unless ($ofile) {
    print "Usage: origo-appbuilder 'origofile'\n";
    exit;
}
unless (-e $ofile) {
    print "Origo file not found: $ofile\n";
    print "Usage: origo-appbuilder 'origofile'\n";
    exit;
}

my $config = ConfigReader::Simple->new($ofile);

# The version of the app we are building
my $version = $config->get("VERSION") || '1.0';
my $baseimage = $config->get("BASEIMAGE");
my $name = $config->get("NAME");
my $appname = $config->get("APPNAME");
my $dir = $config->get("DIR");
my $dirtarget = $config->get("DIRTARGET") || '/';
my $tar = $config->get("TAR");
my $tartarget = $config->get("TARTARGET") || '/';
my $git = $config->get("GIT");
my $gittarget = $config->get("GITTARGET") || '/';
my $debs = $config->get("DEBS");
my $preexec = $config->get("PREEXEC");
my $postexec = $config->get("POSTEXEC");
my $service = $config->get("SERVICE");


my $dname="$name.$version.origo";

# Load nbd
print `modprobe nbd max_part=63`;

# Make base image available in fuel
print ">> Asking Valve to link $baseimage\n";
my $json = `curl --silent -k "https://10.0.0.1/steamengine/images/?action=linkmaster&image=$baseimage"`;

my $jobj = from_json($json);
my $linkpath = $jobj->{linkpath};
my $basepath = $jobj->{path};
my $masterpath = $jobj->{masterpath};

unless ($basepath) {
    print ">> No base path received\n";
    print $json, "\n";
    exit 0;
}

while (!(-e $basepath)) {
  print ">> Waiting for $basepath...\n";
  sleep 1
}

# Clone base image
if (-e "$dname.master.qcow2") {
    print ">> Destination image already exists: $dname.master.qcow2\n";
} else {
    print `qemu-img create -f qcow2 -b "$basepath" "$dname.master.qcow2"`;
}

# Wait for nbd0 to be created
if (!(-e "/dev/nbd0p1")) {
    print `qemu-nbd -c /dev/nbd0 "$dname.master.qcow2"`;
    while (!(-e "/dev/nbd0p1")) {
      print ">> Waiting for nbd0p1...\n";
      sleep 1
    }
}

# Mount image
print `mkdir /tmp/$dname` unless (-d "/tmp/$dname");
print `mount /dev/nbd0p1 /tmp/$dname` unless (-e "/tmp/$dname/boot");

# Run pre exec script
if ($preexec) {
    print "Running pre exec in /tmp/$dname\n";
    foreach my $line (split(/\\n/, $preexec)) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        $line =~ s/#.+$//;
        $line =~ s/\|/\|chroot "\/tmp\/$dname" /;
        $line =~ s/\> */\> \/tmp\/$dname/;
        $line =~ s/\< */\> \/tmp\/$dname/;
        $line =~ s/\$\((.+)\)/\$(chroot "\/tmp\/$dname" $1) /;
        if ($line) {
            my $cmd = qq|chroot "/tmp/$dname" $line|;
            print ">> $cmd\n";
            print `$cmd`;
        }
    }
}

# Install debs
if ($debs) {
    print ">> Installing packages\n";
    print `chroot /tmp/$dname apt-get update`;
    print `chroot /tmp/$dname apt-get -q -y --force-yes --show-progress install $debs`;
}

# Copy files
if ($dir && -e $dir) {
    print ">> Copying files...\n";
    print `tar rvf /tmp/$dname.tar $dir`;
    print `tar xf /tmp/$dname.tar -C /tmp/$dname/$dirtarget`;
    print `rm /tmp/$dname.tar`;
}

# Unpack tar
if ($tar && -e $tar) {
    print ">> Unpacking files...\n";
    print `tar xf $tar -C /tmp/$dname/$tartarget`;
}

# Git clone
if ($git) {
    print ">> Cloning from Git repo...\n";
    print `git clone $git $gittarget`;
}

# Run post exec script
if ($postexec) {
    print "Running post exec in /tmp/$dname\n";
    foreach my $line (split(/\\n/, $postexec)) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        $line =~ s/#.+$//;
        $line =~ s/\|/\|chroot "\/tmp\/$dname" /;
        $line =~ s/\> */\> \/tmp\/$dname/;
        $line =~ s/\< */\> \/tmp\/$dname/;
        $line =~ s/\$\((.+)\)/\$(chroot "\/tmp\/$dname" $1) /;
        if ($line) {
            my $cmd = qq|chroot "/tmp/$dname" $line|;
            print ">> $cmd\n";
            print `$cmd`;
        }
    }
}

# Install boot exec script
if ($service) {
    my $cmd =  <<END
[Unit]
DefaultDependencies=no
Description=Origo $dname
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=$service
TimeoutSec=0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
END
;
    `echo "$cmd" > /tmp/$dname/etc/systemd/system/origo-$dname.service`;
	`chmod 664 /tmp/$dname/etc/systemd/system/origo-$dname.service`;
	`chmod 755 /tmp/$dname$service`;
}

# Unmount base image and clean up
print `umount /tmp/$dname`;
print `killall qemu-nbd`;
print `rm -d /tmp/$dname`;

# convert to qcow2
print "Converting $dname.master.qcow2\n";
print `qemu-img amend -f qcow2 -o compat=0.10 $dname.master.qcow2`;

# Rebasing and activating image
print `qemu-img rebase -f qcow2 -u -b "$masterpath" "$dname.master.qcow2"`;
$appname = uri_escape($appname);
print `curl --silent -k "https://10.0.0.1/steamengine/images?action=activate&image=$cwd/$dname.master.qcow2&name=$appname"`;
