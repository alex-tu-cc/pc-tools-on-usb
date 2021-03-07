#!/bin/sh
set -x
RP="/cdrom"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --allow-unauthenticated --allow-downgrades oem-fix-misc-cnl-oem-image-helper

echo "postfix postfix/mailname string staging-server" | debconf-set-selections
echo "postfix postfix/main_mailer_type string \'Internet Site\'" | debconf-set-selections
oem-install --local-archive $RP/checkbox-pkgs --deb-folder  $RP/maas-pkgs/

