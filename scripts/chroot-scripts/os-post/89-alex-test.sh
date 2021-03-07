#!/bin/sh

set -x
RP="/cdrom"
export DEBIAN_FRONTEND=noninteractive

# for personal convenient, I would like to install oem-helper
#if ! apt-get install -y --allow-unauthenticated --allow-downgrades oem-fix-misc-cnl-oem-image-helper ; then
# apt-get purge -y oem-image-helper || true
# dpkg -i $RP/alex-debs/oem-fix-misc-cnl-oem-image-helper*.deb
#fi

# remove unattend update which could block testing.
#apt-get purge -y unattended-upgrades
python3 /$RP/my-scripts/disable-uattu.py

# prepare sshkey
mkdir -p /etc/ssh/sshd_config.d
cp /$RP/personal_tmp/pc_sanity.conf /etc/ssh/sshd_config.d/
cp /$RP/personal_tmp/authorized_keys /etc/ssh/authorized_keys
