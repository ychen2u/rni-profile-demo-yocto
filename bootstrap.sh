#!/bin/bash

#this is provided while using Utility OS
source /opt/bootstrap/functions

PROVISION_LOG="/tmp/provisioning.log"
run "Begin provisioning process..." \
    "sleep 0.5" \
    ${PROVISION_LOG}

PROVISIONER=$1

# --- Get kernel parameters ---
kernel_params=$(cat /proc/cmdline)

if [[ $kernel_params == *"proxy="* ]]; then
    tmp="${kernel_params##*proxy=}"
    param_proxy="${tmp%% *}"

    export http_proxy=${param_proxy}
    export https_proxy=${param_proxy}
    export no_proxy="localhost,127.0.0.1,${PROVISIONER}"
    export HTTP_PROXY=${param_proxy}
    export HTTPS_PROXY=${param_proxy}
    export NO_PROXY="localhost,127.0.0.1,${PROVISIONER}"
    export DOCKER_PROXY_ENV="--env http_proxy='${http_proxy}' --env https_proxy='${https_proxy}' --env no_proxy='${no_proxy}' --env HTTP_PROXY='${HTTP_PROXY}' --env HTTPS_PROXY='${HTTPS_PROXY}' --env NO_PROXY='${NO_PROXY}'"
    export INLINE_PROXY="export http_proxy='${http_proxy}'; export https_proxy='${https_proxy}'; export no_proxy='${no_proxy}'; export HTTP_PROXY='${HTTP_PROXY}'; export HTTPS_PROXY='${HTTPS_PROXY}'; export NO_PROXY='${NO_PROXY}';"
elif [ $(
    nc -vz ${PROVISIONER} 3128
    echo $?
) -eq 0 ]; then
    export http_proxy=http://${PROVISIONER}:3128/
    export https_proxy=http://${PROVISIONER}:3128/
    export no_proxy="localhost,127.0.0.1,${PROVISIONER}"
    export HTTP_PROXY=http://${PROVISIONER}:3128/
    export HTTPS_PROXY=http://${PROVISIONER}:3128/
    export NO_PROXY="localhost,127.0.0.1,${PROVISIONER}"
    export DOCKER_PROXY_ENV="--env http_proxy='${http_proxy}' --env https_proxy='${https_proxy}' --env no_proxy='${no_proxy}' --env HTTP_PROXY='${HTTP_PROXY}' --env HTTPS_PROXY='${HTTPS_PROXY}' --env NO_PROXY='${NO_PROXY}'"
    export INLINE_PROXY="export http_proxy='${http_proxy}'; export https_proxy='${https_proxy}'; export no_proxy='${no_proxy}'; export HTTP_PROXY='${HTTP_PROXY}'; export HTTPS_PROXY='${HTTPS_PROXY}'; export NO_PROXY='${NO_PROXY}';"
fi

if [[ $kernel_params == *"proxysocks="* ]]; then
    tmp="${kernel_params##*proxysocks=}"
    param_proxysocks="${tmp%% *}"

    export FTP_PROXY=${param_proxysocks}

    tmp_socks=$(echo ${param_proxysocks} | sed "s#http://##g" | sed "s#https://##g" | sed "s#/##g")
    export SSH_PROXY_CMD="-o ProxyCommand='nc -x ${tmp_socks} %h %p'"
fi

if [[ $kernel_params == *"httppath="* ]]; then
    tmp="${kernel_params##*httppath=}"
    param_httppath="${tmp%% *}"
fi

if [[ $kernel_params == *"parttype="* ]]; then
    tmp="${kernel_params##*parttype=}"
    param_parttype="${tmp%% *}"
elif [ -d /sys/firmware/efi ]; then
    param_parttype="efi"
else
    param_parttype="msdos"
fi

if [[ $kernel_params == *"bootstrap="* ]]; then
    tmp="${kernel_params##*bootstrap=}"
    param_bootstrap="${tmp%% *}"
    param_bootstrapurl=$(echo $param_bootstrap | sed "s#/$(basename $param_bootstrap)\$##g")
fi

if [[ $kernel_params == *"token="* ]]; then
    tmp="${kernel_params##*token=}"
    param_token="${tmp%% *}"
fi

if [[ $kernel_params == *"agent="* ]]; then
    tmp="${kernel_params##*agent=}"
    param_agent="${tmp%% *}"
else
    param_agent="master"
fi

if [[ $kernel_params == *"kernparam="* ]]; then
    tmp="${kernel_params##*kernparam=}"
    temp_param_kernparam="${tmp%% *}"
    param_kernparam=$(echo ${temp_param_kernparam} | sed 's/#/ /g' | sed 's/:/=/g')
fi

if [[ $kernel_params == *"arch="* ]]; then
    tmp="${kernel_params##*arch=}"
    param_arch="${tmp%% *}"
else
    param_arch="amd64"
fi

if [[ $kernel_params == *"insecurereg="* ]]; then
    tmp="${kernel_params##*insecurereg=}"
    param_insecurereg="${tmp%% *}"
fi

if [[ $kernel_params == *"username="* ]]; then
    tmp="${kernel_params##*username=}"
    param_username="${tmp%% *}"
else
    param_username="sys-admin"
fi

if [[ $kernel_params == *"password="* ]]; then
    tmp="${kernel_params##*password=}"
    param_password="${tmp%% *}"
else
    param_password="password"
fi

if [[ $kernel_params == *"debug="* ]]; then
    tmp="${kernel_params##*debug=}"
    param_debug="${tmp%% *}"
fi

if [[ $kernel_params == *"release="* ]]; then
    tmp="${kernel_params##*release=}"
    param_release="${tmp%% *}"
else
    param_release='dev'
fi

if [[ $param_release == 'prod' ]]; then
    kernel_params="$param_kernparam" # ipv6.disable=1
else
    kernel_params="$param_kernparam"
fi

# --- Config

# --- Get free memory
freemem=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# We need 200 Mb for the boot partition
boot_size=200

# 50% for the second rootfs
testfs_ratio=50

found="no"

echo "Searching for a hard drive..."
for device in 'hda' 'hdb' 'sda' 'sdb' 'mmcblk0' 'mmcblk1'
do
    if [ -e /sys/block/${device}/removable ]; then
        if [ "$(cat /sys/block/${device}/removable)" = "0" ]; then
            found="yes"

            while true; do
                # Try sleeping here to avoid getting kernel messages
                # obscuring/confusing user
                sleep 5
                echo "Found drive at /dev/${device}. Do you want to install this image there? [y/n]"
                read answer
                if [ "$answer" = "y" ] ; then
                    break
                fi

                if [ "$answer" = "n" ] ; then
                    found=no
                    break
                fi

                echo "Please answer y or n"
            done
        fi
    fi

    if [ "$found" = "yes" ]; then
        break;
    fi

done

if [ "$found" = "no" ]; then
    exit 1
fi

echo "Installing image on /dev/${device}"

#
# The udev automounter can cause pain here, kill it
#
rm -f /etc/udev/rules.d/automount.rules
rm -f /etc/udev/scripts/mount*

#
# Unmount anything the automounter had mounted
#
umount /dev/${device}* 2> /dev/null || /bin/true

mkdir -p /tmp
cat /proc/mounts > /etc/mtab

disk_size=$(parted /dev/${device} unit mb print | grep '^Disk .*: .*MB' | cut -d" " -f 3 | sed -e "s/MB//")

testfs_size=$((disk_size*testfs_ratio/100))
rootfs_size=$((disk_size-boot_size-testfs_size))

rootfs_start=$((boot_size))
rootfs_end=$((rootfs_start+rootfs_size))
testfs_start=$((rootfs_end))

# MMC devices are special in a couple of ways
# 1) they use a partition prefix character 'p'
# 2) they are detected asynchronously (need rootwait)
rootwait=""
part_prefix=""
if [ ! "${device#mmcblk}" = "${device}" ]; then
    part_prefix="p"
    rootwait="rootwait"
fi
bootfs=/dev/${device}${part_prefix}1
rootfs=/dev/${device}${part_prefix}2
testfs=/dev/${device}${part_prefix}3

echo "*****************"
echo "Boot partition size:   $boot_size MB ($bootfs)"
echo "Rootfs partition size: $rootfs_size MB ($rootfs)"
echo "Testfs partition size:   $testfs_size MB ($testfs)"
echo "*****************"
echo "Deleting partition table on /dev/${device} ..."
dd if=/dev/zero of=/dev/${device} bs=512 count=2

echo "Creating new partition table on /dev/${device} ..."
parted /dev/${device} mklabel gpt

echo "Creating boot partition on $bootfs"
parted /dev/${device} mkpart primary 0% $boot_size
parted /dev/${device} set 1 boot on

echo "Creating rootfs partition on $rootfs"
parted /dev/${device} mkpart primary $rootfs_start $rootfs_end

echo "Creating testfs partition on $testfs"
parted /dev/${device} mkpart primary $testfs_start 100%

parted /dev/${device} print

echo "Formatting $bootfs to vfat..."
mkfs.vfat -n "boot" $bootfs

echo "Formatting $rootfs to ext3..."
mkfs.ext3 -L "platform" $rootfs

echo "Formatting $testfs to ext3..."
mkfs.ext3 -L "testrootfs" $testfs

# Start to install
export TGT_BOOT=/target/boot
export TGT_ROOT=/target/root

mkdir -p $TGT_BOOT
mkdir -p $TGT_ROOT
mkdir /rootmnt
mount $bootfs $TGT_BOOT
mount $rootfs $TGT_ROOT

# Download install files
export INSTALL_FILES=$TGT_ROOT/installfiles
mkdir -p $INSTALL_FILES
wget  http://dcp-dev.intel.com/pub/users-share/chenyan/stx-testfarm/bm/ -P bm
wget -O $INSTALL_FILES/rootfs.img $param_bootstrapurl/files/rootfs.img
wget -O $INSTALL_FILES/bzImage $param_bootstrapurl/files/bzImage
wget -P $INSTALL_FILES/EFI -nH -np -r --cut-dirs=5 $param_bootstrapurl/files/EFI
wget -P $INSTALL_FILES/loader -nH -np -r --cut-dirs=5 $param_bootstrapurl/files/loader


# Copy rootfs
mount -o rw,loop,noatime,nodiratime $INSTALL_FILES/rootfs.img /rootmnt

echo "Copying rootfs files..."
cp -a /rootmnt/* $TGT_ROOT

touch $TGT_ROOT/etc/masterimage
if [ -d $TGT_ROOT/etc/ ] ; then
    # We dont want udev to mount our root device while we're booting...
    if [ -d $TGT_ROOT/etc/udev/ ] ; then
        echo "/dev/${device}" >> $TGT_ROOT/etc/udev/mount.blacklist
    fi
fi

umount /rootmnt

# Prepare boot partition
echo "Preparing boot partition..."

EFIDIR="$TGT_BOOT/EFI/BOOT"
mkdir -p $EFIDIR
cp $INSTALL_FILES/bzImage $TGT_BOOT
# Copy the efi loader
cp $INSTALL_FILES/EFI/BOOT/*.efi $EFIDIR

if [ -f $INSTALL_FILES/EFI/BOOT/grub.cfg ]; then
    GRUBCFG="$EFIDIR/grub.cfg"
    cp $INSTALL_FILES/EFI/BOOT/grub.cfg $GRUBCFG
    # Update grub config for the installed image
    # Delete the install entry
    sed -i "/menuentry 'install'/,/^}/d" $GRUBCFG
    # Delete the initrd lines
    sed -i "/initrd /d" $GRUBCFG
    # Delete any LABEL= strings
    sed -i "s/ LABEL=[^ ]*/ /" $GRUBCFG
    # Delete any root= strings
    sed -i "s/ root=[^ ]*/ /" $GRUBCFG
    # Add the root= and other standard boot options
    sed -i "s@linux /vmlinuz *@linux /vmlinuz root=$rootfs rw $rootwait quiet @" $GRUBCFG
fi

if [ -d $INSTALL_FILES/loader ]; then
    SYSTEMDBOOT_CFGS="$TGT_BOOT/loader/entries/*.conf"
    # copy config files for systemd-boot
    cp -dr $INSTALL_FILES/loader $TGT_BOOT
    # delete the install entry
    rm -f $TGT_BOOT/loader/entries/install.conf
    # delete the initrd lines
    sed -i "/initrd /d" $SYSTEMDBOOT_CFGS
    # delete any LABEL= strings
    sed -i "s/ LABEL=[^ ]*/ /" $SYSTEMDBOOT_CFGS
    # delete any root= strings
    sed -i "s/ root=[^ ]*/ /" $SYSTEMDBOOT_CFGS
    # add the root= and other standard boot options
    sed -i "s@options *@options root=$rootfs rw $rootwait quiet @" $SYSTEMDBOOT_CFGS
    # Add the test label
    echo -ne "title test\nlinux /test-kernel\noptions root=$testfs rw $rootwait quiet\n" > $TGT_BOOT/loader/entries/test.conf
fi

umount $TGT_BOOT
rm -rf $INSTALL_FILES
umount $TGT_ROOT

sync

echo "Rebooting..."
reboot -f
