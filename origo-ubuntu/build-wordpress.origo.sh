#!/bin/bash

# The version of the app we are building
version="1.3"

dname="origo-wordpress.o"
baseimg="/mnt/fuel/pool3/origo-xenial.small.master.qcow2"

# Change working directory to script's directory
cd ${0%/*}

# Clone base image
kvm-img create -f qcow2 -b "$baseimg" "$dname.master.qcow2"

# Mount image
mkdir $dname
modprobe nbd max_part=63
qemu-nbd -c /dev/nbd0 "$dname.master.qcow2"
mount /dev/nbd0p1 $dname

# Include all the modules we want installed for this app
tar rvf $dname.wbm.tar origo/tabs/wordpress
gzip -f $dname.wbm.tar
cp -a $dname.wbm.tar.gz $1/tmp/origo.wbm.tar.gz
tar -zxf /tmp/origo.wbm.tar.gz -C $dname/usr/share/webmin

# Unmount base image
#umount /mnt/image
#vgchange -an VolGroupName
#killall qemu-nbd
