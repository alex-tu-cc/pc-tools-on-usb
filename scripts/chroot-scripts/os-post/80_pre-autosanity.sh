#!/bin/sh
set -x
RP="/cdrom"
export DEBIAN_FRONTEND=noninteractive
if ! apt-get install -y --allow-unauthenticated --allow-downgrades oem-fix-misc-cnl-oem-image-helper ; then
 apt-get purge -y oem-image-helper
 dpkg -i $RP/maas-pkgs/oem-fix-misc-cnl-oem-image-helper*.deb
fi

python3 /$RP/pc-sanity-scripts/disable-uattu.py
