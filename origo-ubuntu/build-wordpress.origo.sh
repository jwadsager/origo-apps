#!/bin/bash

# The version of the app we are building
version="1.0"

dname="origo-wordpress.o"
baseimg="/mnt/fuel/pool3/origo-xenial.small-1.4.master.qcow2"

# Change working directory to script's directory
cd ${0%/*}

# Clone base image
qemu-img create -f qcow2 -b "$baseimg" "$dname.master.qcow2"

# Load nbd
modprobe nbd max_part=63
qemu-nbd -c /dev/nbd0 "$dname.master.qcow2"

# Wait for nbd0 to be created
while [ ! -e "/dev/nbd0p1" ]
do
  echo "Waiting for nbd0p1..."
  sleep 1
done

# Mount image
mkdir $dname
mount /dev/nbd0p1 $dname

# Include all the modules we want installed for this app
tar rvf $dname.wbm.tar origo/tabs/wordpress
gzip -f $dname.wbm.tar
tar -zxf $dname.wbm.tar.gz -C $dname/usr/share/webmin

# Unmount base image
umount $dname
killall qemu-nbd
rm -d $dname
rm $dname.wbm.tar.gz
