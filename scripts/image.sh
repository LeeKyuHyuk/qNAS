#!/bin/bash
#
# QNAS system build script
# Optional parameteres below:

set -o nounset
set -o errexit

# End of optional parameters
function step() {
  echo -e "\e[7m\e[1m>>> $1\e[0m"
}

function success() {
  echo -e "\e[1m\e[32m$1\e[0m"
}

function error() {
  echo -e "\e[1m\e[31m$1\e[0m"
}

function extract() {
  case $1 in
    *.tgz) tar -zxf $1 -C $2 ;;
    *.tar.gz) tar -zxf $1 -C $2 ;;
    *.tar.bz2) tar -jxf $1 -C $2 ;;
    *.tar.xz) tar -Jxf $1 -C $2 ;;
  esac
}

function check_environment_variable {
  if ! [[ -d $SOURCES_DIR ]] ; then
    error "Please download tarball files!"
    error "Run 'make download'."
    exit 1
  fi

  if ! [[ -d $TOOLS_DIR ]] ; then
    error "Can't find tools directory!"
    error "Run 'make toolchain'."
  fi
}

function timer {
  if [[ $# -eq 0 ]]; then
    echo $(date '+%s')
  else
    local stime=$1
    etime=$(date '+%s')
    if [[ -z "$stime" ]]; then stime=$etime; fi
    dt=$((etime - stime))
    ds=$((dt % 60))
    dm=$(((dt / 60) % 60))
    dh=$((dt / 3600))
    printf '%02d:%02d:%02d' $dh $dm $ds
  fi
}

check_environment_variable
total_build_time=$(timer)

export CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc"
export CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++"
export AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar"
export AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as"
export LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld"
export RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib"
export READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf"
export STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip"

rm -rf $BUILD_DIR $IMAGES_DIR
mkdir -pv $BUILD_DIR $IMAGES_DIR

step "[2/] Generate Root File System"
mkdir -pv $IMAGES_DIR/rootfs/{dev,etc/autorun,lib,mnt,proc,root,sys,tmp,var/log}
if [[ "$CONFIG_LINUX_ARCH" = "i386" ]] ; then
    ln -snvf lib $IMAGES_DIR/rootfs/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "x86_64" ]] ; then
    ln -snvf lib $IMAGES_DIR/rootfs/lib64
fi

step "Copy necessary ibrary"
cp -v $SYSROOT_DIR/lib/libc-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf libc-2.30.so $IMAGES_DIR/rootfs/lib/libc.so.6
cp -v $SYSROOT_DIR/lib/libm-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf libm-2.30.so $IMAGES_DIR/rootfs/lib/libm.so.6
cp -v $SYSROOT_DIR/lib/libresolv-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf libresolv-2.30.so $IMAGES_DIR/rootfs/lib/libresolv.so.2
cp -v $SYSROOT_DIR/lib/ld-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf ld-2.30.so $IMAGES_DIR/rootfs/lib/ld-linux-x86-64.so.2
cp -v $SYSROOT_DIR/lib/libnss_dns-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf libnss_dns-2.30.so $IMAGES_DIR/rootfs/lib/libnss_dns.so
ln -snvf libnss_dns-2.30.so $IMAGES_DIR/rootfs/lib/libnss_dns.so.2
cp -v $SYSROOT_DIR/lib/libnss_files-2.30.so $IMAGES_DIR/rootfs/lib
ln -snvf libnss_files-2.30.so $IMAGES_DIR/rootfs/lib/libnss_files.so
ln -snvf libnss_files-2.30.so $IMAGES_DIR/rootfs/lib/libnss_files.so.2

step "[1/] Busybox 1.31.1"
extract $SOURCES_DIR/busybox-1.31.1.tar.bz2 $BUILD_DIR
make -j$PARALLEL_JOBS distclean -C $BUILD_DIR/busybox-1.31.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" defconfig -C $BUILD_DIR/busybox-1.31.1
sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" $BUILD_DIR/busybox-1.31.1/.config
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/busybox-1.31.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" CONFIG_PREFIX="$IMAGES_DIR/rootfs" install -C $BUILD_DIR/busybox-1.31.1
cp -v $BUILD_DIR/busybox-1.31.1/examples/depmod.pl $TOOLS_DIR/bin
# Remove 'linuxrc' which is used when we boot in 'RAM disk' mode.
rm -fv $IMAGES_DIR/rootfs/linuxrc
rm -rf $BUILD_DIR/busybox-1.31.1

# Create /init
cat > $IMAGES_DIR/rootfs/init << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init (this file)
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/02_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/03_bootscript.sh
#                    |       |
#                    |       +-- /etc/autorun/* (all scripts)
#                    |
#                    +--(2) /bin/sh (Alt + F1, main console)
#                    |
#                    +--(2) /bin/sh (Alt + F2)
#                    |
#                    +--(2) /bin/sh (Alt + F3)
#                    |
#                    +--(2) /bin/sh (Alt + F4)

echo -e "Welcome to \\e[1mQNAS \\e[32mAbsinthe \\e[0m\\e[1mInstaller\\e[0m (/init)"

# Let's mount all core file systems.
/etc/01_prepare.sh

# Create new mountpoint in RAM, make it our new root location and overlay it
# with our storage area (if overlay area exists at all). This operation invokes
# the script '/etc/02_init.sh' as the new init process.
exec /etc/02_init.sh
EOF
chmod 755 -v $IMAGES_DIR/rootfs/init

# Create /etc/01_prepare.sh
cat > $IMAGES_DIR/rootfs/etc/01_prepare.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh (this file)
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/02_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/03_bootscript.sh
#                    |       |
#                    |       +-- /etc/autorun/* (all scripts)
#                    |
#                    +--(2) /bin/sh (Alt + F1, main console)
#                    |
#                    +--(2) /bin/sh (Alt + F2)
#                    |
#                    +--(2) /bin/sh (Alt + F3)
#                    |
#                    +--(2) /bin/sh (Alt + F4)

dmesg -n 1
echo "Most kernel messages have been suppressed."

mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t tmpfs none /tmp -o mode=1777
mount -t sysfs none /sys

mkdir -p /dev/pts

mount -t devpts none /dev/pts

echo "Mounted all core filesystems. Ready to continue."
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/01_prepare.sh

# Create /etc/02_init.sh
cat > $IMAGES_DIR/rootfs/etc/02_init.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/02_init.sh (this file)
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/03_bootscript.sh
#                    |       |
#                    |       +-- /etc/autorun/* (all scripts)
#                    |
#                    +--(2) /bin/sh (Alt + F1, main console)
#                    |
#                    +--(2) /bin/sh (Alt + F2)
#                    |
#                    +--(2) /bin/sh (Alt + F3)
#                    |
#                    +--(2) /bin/sh (Alt + F4)

# If you have persistent overlay support then you can edit this file and replace
# the default initialization  of the system. For example, you could use this:
#
# exec setsid cttyhach sh
#
# This gives you PID 1 shell inside the initramfs area. Since this is a PID 1
# shell, you can still invoke the original initialization logic by executing
# this command:
#
# exec /sbin/init

# Use default initialization logic based on configuration in '/etc/inittab'.
echo -e "Executing \\e[32m/sbin/init\\e[0m as PID 1."
exec /sbin/init
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/02_init.sh

# Create /etc/03_bootscript.sh
cat > $IMAGES_DIR/rootfs/etc/03_bootscript.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/02_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/03_bootscript.sh (this file)
#                    |       |
#                    |       +-- /etc/autorun/* (all scripts)
#                    |
#                    +--(2) /bin/sh (Alt + F1, main console)
#                    |
#                    +--(2) /bin/sh (Alt + F2)
#                    |
#                    +--(2) /bin/sh (Alt + F3)
#                    |
#                    +--(2) /bin/sh (Alt + F4)

echo -e "Welcome to \\e[1mQNAS \\e[32mAbsinthe \\e[0m\\e[1mInstaller\\e[0m (/sbin/init)"

# Autorun functionality
if [ -d /etc/autorun ] ; then
    for AUTOSCRIPT in /etc/autorun/*
    do
        if [ -f "$AUTOSCRIPT" ] && [ -x "$AUTOSCRIPT" ]; then
            echo -e "Executing \\e[32m$AUTOSCRIPT\\e[0m in subshell."
            $AUTOSCRIPT
        fi
    done
fi
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/03_bootscript.sh


# Create /etc/03_bootscript.sh
cat > $IMAGES_DIR/rootfs/etc/04_rc.dhcp << "EOF"
#!/bin/sh

# This script gets called by udhcpc to setup the network interfaces

ip addr add $ip/$mask dev $interface

if [ "$router" ]; then
  ip route add default via $router dev $interface
fi

if [ "$ip" ]; then
  echo -e "DHCP configuration for device $interface"
  echo -e "IP:     \\e[1m$ip\\e[0m"
  echo -e "mask:   \\e[1m$mask\\e[0m"
  echo -e "router: \\e[1m$router\\e[0m"
fi
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/04_rc.dhcp

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/inittab << "EOF"
::sysinit:/etc/03_bootscript.sh
::restart:/sbin/init
::shutdown:echo -e "\nSyncing all file buffers."
::shutdown:sync
::shutdown:echo "Unmounting all filesystems."
::shutdown:umount -a -r
::shutdown:echo -e "\n  \\e[1mQuit QNAS Installer\\e[0m\n"
::shutdown:sleep 1
::ctrlaltdel:/sbin/reboot
::once:cat /etc/motd
::respawn:/bin/cttyhack /bin/sh
tty2::once:cat /etc/motd
tty2::respawn:/bin/sh
tty3::once:cat /etc/motd
tty3::respawn:/bin/sh
tty4::once:cat /etc/motd
tty4::respawn:/bin/sh
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/inittab

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/hosts << "EOF"
# /etc/hosts
127.0.0.1	localhost

# ipv6
::1	localhost ipv6-localhost
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/hosts

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/nsswitch.conf << "EOF"
hosts:		files dns
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/nsswitch.conf

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/resolv.conf << "EOF"
# The number of active DNS resolvers is limited to 3.
#
#   https://linux.die.net/man/5/resolv.conf

# Google Public DNS
# http://developers.google.com/speed/public-dns
nameserver 8.8.8.8
#nameserver 8.8.4.4

# CloudFlare DNS
# http://blog.cloudflare.com/announcing-1111
nameserver 1.1.1.1
#nameserver 1.0.0.1

# Quad9 DNS
# http://quad9.net
nameserver 9.9.9.9
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/resolv.conf

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/autorun/20_network.sh << "EOF"
#!/bin/sh

# DHCP network
for DEVICE in /sys/class/net/* ; do
  echo "Found network device ${DEVICE##*/}"
  ip link set ${DEVICE##*/} up
  [ ${DEVICE##*/} != lo ] && udhcpc -b -i ${DEVICE##*/} -s /etc/04_rc.dhcp
done
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/autorun/20_network.sh

# /etc/motd
cat > $IMAGES_DIR/rootfs/etc/motd << "EOF"
[0m
  ########################################
  #                                      #
  #  Welcome to [1mQNAS [32mAbsinthe [0m[1mInstaller[0m  #
  #                                      #
  ########################################
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/motd

# Create /var/log/{btmp,lastlog,messages,utmp,wtmp}
touch $IMAGES_DIR/rootfs/var/log/{btmp,lastlog,messages,utmp,wtmp}
chmod 644 -v $IMAGES_DIR/rootfs/var/log/{btmp,lastlog,messages,utmp,wtmp}

step "[3/] Pack Root File System"
( cd $IMAGES_DIR/rootfs && find . | cpio -R root:root -H newc -o | xz -9 --check=none > $IMAGES_DIR/rootfs.cpio.xz )
rm -rf $IMAGES_DIR/rootfs

step "[4/] ISO Overlay Structure"
mkdir -p $IMAGES_DIR/isoimage/qnas/{rootfs,work}
touch $IMAGES_DIR/isoimage/qnas/rootfs/QNAS_README

step "[5/] Generate UEFI Image"
# Find the kernel size in bytes.
kernel_size=`du -b $KERNEL_DIR/bzImage | awk '{print \$1}'`
# Find the initramfs size in bytes.
rootfs_size=`du -b $IMAGES_DIR/rootfs.cpio.xz | awk '{print \$1}'`
loader_size=`du -b $SUPPORT_DIR/systemd-boot/BOOTx64.EFI | awk '{print \$1}'`
# The EFI boot image is 64KB bigger than the kernel size.
image_size=$((kernel_size + rootfs_size + loader_size + 65536))
truncate -s $image_size $IMAGES_DIR/uefi.img
mkfs.vfat $IMAGES_DIR/uefi.img
mkdir -pv $IMAGES_DIR/uefi
step "Copy Kernel and Root File System"
mkdir -pv $IMAGES_DIR/uefi/qnas/x86_64
cp -v $KERNEL_DIR/bzImage $IMAGES_DIR/uefi/qnas/x86_64/kernel.xz
mv -v $IMAGES_DIR/rootfs.cpio.xz $IMAGES_DIR/uefi/qnas/x86_64/rootfs.xz
step "Copy 'systemd-boot' UEFI Boot Loader"
mkdir -pv $IMAGES_DIR/uefi/EFI/BOOT
cp -v $SUPPORT_DIR/systemd-boot/BOOTx64.EFI $IMAGES_DIR/uefi/EFI/BOOT
step "'systemd-boot' Configuration"
mkdir -pv $IMAGES_DIR/uefi/loader/entries
cat > $IMAGES_DIR/uefi/loader/loader.conf << "EOF"
default qnas-x86_64
timeout 5
editor 0
EOF
cat > $IMAGES_DIR/uefi/loader/entries/qnas-x86_64.conf << "EOF"
title QNAS 1.0.0 (Absinthe) Installer
version x86_64
efi /qnas/x86_64/kernel.xz
options initrd=/qnas/x86_64/rootfs.xz
EOF
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/loader ::loader
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/EFI ::EFI
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/qnas ::qnas

rm -rf $IMAGES_DIR/uefi
chmod ugo+r -v $IMAGES_DIR/uefi.img
mkdir -pv $IMAGES_DIR/isoimage/boot
mv -v $IMAGES_DIR/uefi.img $IMAGES_DIR/isoimage/boot

step "[6/] Generate ISO Image"
extract $SOURCES_DIR/syslinux-6.03.tar.xz $BUILD_DIR
xorriso -as mkisofs \
  -isohybrid-mbr $BUILD_DIR/syslinux-6.03/bios/mbr/isohdpfx.bin \
  -c boot/boot.cat \
  -e boot/uefi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
  -o $IMAGES_DIR/$CONFIG_ISO_FILENAME.iso \
  $IMAGES_DIR/isoimage
rm -rf $IMAGES_DIR/isoimage

success "\nTotal QNAS image generate time: $(timer $total_build_time)\n"
