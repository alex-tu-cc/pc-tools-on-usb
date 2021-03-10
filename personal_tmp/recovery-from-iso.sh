#!/bin/bash
set -ex

jenkins_job_for_iso="dell-bto-focal-fossa-edge-alloem"
jenkins_job_build_no="lastSuccessfulBuild"
jenkins_url="10.101.46.50"
user_on_target="ubuntu"
SSH="ssh -o StrictHostKeyChecking=no"
SCP="scp -o StrictHostKeyChecking=no"
temp_folder="$(mktemp -d -p "$PWD")"
GIT="git -C $temp_folder"
#TAR="tar -C $temp_folder"
script_on_target_machine="inject_recovery_from_iso.sh"
eval set -- $(getopt -o "hj:t:b:" -l "help,target-ip:,jenkins-job:,local-iso:" -- $@)

usage() {
cat << EOF
usage:
$(basename "$0") -j <jenkins-job-name> -b <jenkins-job-build-no> -t <target-ip> [-h|--help] [--dry-run]
$(basename "$0") --local-iso <path to local iso file> -t <target-ip> [-h|--help] [--dry-run]

Limition:
    It will failed when target recovery partition size smaller than target iso file.

The assumption of using this tool:
 - An root account 'ubuntu' on target machine.
 - The root account 'ubuntu' can execute command with root permission with \`sudo\` without password.
 - Host executing this tool can access target machine without password over ssh.

OPTIONS:
    -j|--jenkins-job            Get iso from jenkins-job. The default is "dell-bto-focal-fossa-edge-alloem".
    -b|--jenkins-job-build-no   The build number of the Jenkins job assigned by -j|--jenkins-job.
    -t|--target-ip  The IP address of target machine. It will be used for ssh accessing.
                    Please put your ssh key on target machine. This tool no yet support keyphase for ssh.
    -h|--help Print this message
    --dry-run Dryrun

    Usage:
    $(basename "$0") -j  dell-bto-focal-fossa-edge-alloem -b 3 -t 192.168.101.68

    $(basename "$0") --local-iso ./dell-bto-focal-fossa-edge-alloem-X73-20210302-3.iso

EOF
exit 1
}

download_preseed() {
    echo " == download_preseed == "
    # AI: put this snapshot to public location

    # get checkbox pkgs and prepare-checkbox
    # $GIT clone git+ssh://alextu@git.launchpad.net/~lyoncore-team/lyoncore/+git/somerville-maas-override --depth 1 -b checkbox-pkgs-focal checkbox-pkgs
    # get pkgs to skip OOBE
    $GIT clone https://github.com/alex-tu-cc/pc-tools-on-usb.git --depth 1 -b oem-fix-misc-cnl-no-secureboot oem-fix-misc-cnl-no-secureboot
    $GIT clone https://github.com/alex-tu-cc/pc-tools-on-usb.git --depth 1 -b oem-fix-misc-cnl-skip-oobe oem-fix-misc-cnl-skip-oobe
    $GIT clone https://github.com/alex-tu-cc/pc-tools-on-usb.git --depth 1 -b oem-fix-misc-cnl-skip-storage-selecting oem-fix-misc-cnl-skip-storage-selecting


    # get pkgs for ssh key and skip disk checking.
    $GIT clone https://github.com/alex-tu-cc/pc-tools-on-usb.git --depth 1 misc_for_automation

    return 0
}
push_preseed() {
    echo " == download_preseed == "
    $SSH "$user_on_target"@"$target_ip" rm -rf push_preseed
    $SSH "$user_on_target"@"$target_ip" mkdir -p push_preseed
    $SSH "$user_on_target"@"$target_ip" touch push_preseed/SUCCSS_push_preseed
    $SSH "$user_on_target"@"$target_ip" sudo rm -f /cdrom/SUCCSS_push_preseed

    for folder in misc_for_automation oem-fix-misc-cnl-no-secureboot oem-fix-misc-cnl-skip-oobe oem-fix-misc-cnl-skip-storage-selecting; do
        tar -C "$temp_folder"/$folder -zcvf "$temp_folder"/$folder.tar.gz .
        $SCP $temp_folder/$folder.tar.gz "$user_on_target"@"$target_ip":~
        $SSH "$user_on_target"@"$target_ip" tar -C push_preseed -zxvf $folder.tar.gz
    done

    $SSH "$user_on_target"@"$target_ip" sudo cp -r push_preseed/* /cdrom/
    return 0
}
inject_preseed() {
    echo " == inject_preseed == "
    download_preseed && \
    push_preseed && \
    scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/cdrom/SUCCSS_push_preseed /tmp || usage
    $SSH "$user_on_target"@"$target_ip" touch /tmp/SUCCSS_inject_preseed
}

inject_recovery_iso() {
    if [ -n "$local_iso" ]; then
        img_name="$(basename "$local_iso")"
        scp -o StrictHostKeyChecking=no "$local_iso" "$user_on_target"@"$target_ip":~/
cat <<EOF > "$temp_folder/$script_on_target_machine"
#!/bin/bash
set -ex
sudo umount /cdrom /mnt || true
sudo mount -o loop $img_name /mnt && \
sudo mount /dev/\$(lsblk -l | grep efi | cut -d ' ' -f 1 | sed 's/.$/2'/) /cdrom && \
df | grep "cdrom\|mnt" | awk '{print \$2" "\$6}' | sort | tail -n1 | grep -q cdrom && \
sudo mkdir -p /var/tmp/rsync && \
sudo rsync -alv /mnt/* /cdrom/. --exclude=factory/grub.cfg* --exclude=efi/boot --exclude=.disk/casper-uuid --exclude=.disk/info --delete --exclude=casper/filesystem.squashfs --temp-dir=/var/tmp/rsync && \
sudo cp /mnt/.disk/ubuntu_dist_channel /cdrom/.disk/ && \
touch /tmp/SUCCSS_inject_recovery_iso
EOF
        scp -o StrictHostKeyChecking=no "$temp_folder"/"$script_on_target_machine" "$user_on_target"@"$target_ip":~/
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" chmod +x "\$HOME/$script_on_target_machine"
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" "\$HOME/$script_on_target_machine"
        scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/tmp/SUCCSS_inject_recovery_iso /tmp || usage
    else
        img_jenkins_out_url="ftp://$jenkins_url/jenkins_host/jobs/$jenkins_job_for_iso/builds/$jenkins_job_build_no/archive/out"
        img_name="$(wget -q "$img_jenkins_out_url/" -O - | grep -o 'href=.*iso"' | awk -F/ '{print $NF}' | tr -d \")"
        wget "$img_jenkins_out_url"/"$img_name.md5sum"
        md5sum -c $img_name.md5sum || wget "$img_jenkins_out_url"/"$img_name"
        md5sum -c $img_name.md5sum || usage
        local_iso="`pwd`/$img_name"
        inject_recovery_iso
    fi
}
prepare() {
    echo "prepare"
    inject_recovery_iso
    inject_preseed
}

poll_recovery_status() {
    while(:); do
        if $SSH "$user_on_target"@"$target_ip" ubuntu-report show; then
           break
        fi
        sleep 180
    done
}

do_recovery() {
    ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" sudo dell-restore-system -y &
    sleep 300 # sleep to make sure the target system has been rebooted to recovery mode.
    poll_recovery_status
}

main() {
    while [ $# -gt 0 ]
    do
        case "$1" in
            --local-iso)
                shift
                local_iso="$1"
                ;;
            -j | --jenkins-job)
                shift
                jenkins_job_for_iso="$1"
                ;;
            -b | --jenkins-job-build-no)
                shift
                jenkins_job_build_no="$1"
                ;;
            -t | --target-ip)
                shift
                target_ip="$1"
                ;;
            -h | --help)
                usage 0
                exit 0
                ;;
            --dry-run)
                DRY_RUN=1;
                ;;
            --)
           ;;
            *)
            echo "Not recognize $1"
            usage
       ;;
           esac
           shift
    done
    prepare
    #do_recovery
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi