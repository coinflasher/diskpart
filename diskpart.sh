#!/bin/bash

disk="sdb"
minpartsize=50

function mk_mount {
  part_num=$1
  mount_name=$2
  if ! [ -d "$mount_name" ]
  then
    mkdir $mount_name
  fi
  if ! grep -q " $mount_name " /etc/fstab
  then
    echo -e "/dev/${disk}${part_num} $mount_name\t\txfs\tdefaults\t1 2" >> /etc/fstab
  fi
}

# Check for root user
curuser=$(whoami)
if [ "$curuser" != "root" ]
then
  echo "";echo "ERROR: You must be root to run this script!"
  exit 1
fi
# validate disk availability and minium disk size
if fdisk -l /dev/${disk} &> /dev/null
then
  disksize=$(fdisk -l /dev/${disk} | head -1 | cut -d , -f 2 | awk {'print $1'})
  diskGB=$(($disksize / 1000000000))
  if (($diskGB < $minpartsize))
  then
    echo "";echo "ERROR: The minimum disk size for /dev/${disk} must be ${minpartsize}GB"
    echo "Current size is: ${diskGB}GB"
    exit 1
  fi
else
  echo "";echo "ERROR: /dev/${disk} was not found!"
  exit 1
fi

# check for exiting partitions
if fdisk -l /dev/${disk}1 &> /dev/null
then
  echo "";echo "ERROR: There are pre-existing partitions on /dev/${disk}"
  echo "You must remove these partitions before proceeding!"
  echo "";echo""
  fdisk -l /dev/${disk}
  exit 1
fi

# build disk configuration
sfdisk -d /dev/${disk} > /tmp/${disk}
echo "
/dev/sdb1 : start=        2048, size=    31455232, type=83
/dev/sdb2 : start=    31457280, size=    20971520, type=83
/dev/sdb3 : start=    52428800, size=     8388608, type=83
/dev/sdb4 : start=    60817408, size=     8388608, type=83" >> /tmp/${disk}

# create disk partitions
sfdisk /dev/${disk} < /tmp/${disk}
if [ "$?" -eq 0 ]
then
  echo ""; echo""; echo "-= Disk partitioning complete =-"
else
  echo "ERROR: Disk patitioning FAILED!"
  exit 1
fi

# Create the filesystems
for part in $(seq 1 4)
do
  mkfs.xfs -f /dev/${disk}${part}
done

# Migrate /home to $disk
cp /etc/fstab /etc/fstab.orig
if ! mount | grep -q "/home"
then
  mkdir /tmp/home
  mount /dev/${disk}2 /tmp/home
  cp -a /home/* /tmp/home/
  rm -Rf /home/*
  if ! grep -q "/home" /etc/fstab
  then
    echo -e "/dev/${disk}2 /home\t\txfs\tdefaults\t1 2" >> /etc/fstab 
  fi
  umount /tmp/home
  mount /home
  rm -Rf /tmp/home
fi

# Create /opt/Tanium, /var/tmp, /tmp

mk_mount 1 /opt/Tanium
mk_mount 3 /var/tmp
mk_mount 4 /tmp

echo "Filesystem creation is complete.  Changes will take effect upon the next reboot"
