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

step "[1/] Busybox 1.31.1"
extract $SOURCES_DIR/busybox-1.31.1.tar.bz2 $BUILD_DIR
make -j$PARALLEL_JOBS distclean -C $BUILD_DIR/busybox-1.31.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" defconfig -C $BUILD_DIR/busybox-1.31.1
sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" $BUILD_DIR/busybox-1.31.1/.config
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/busybox-1.31.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" CONFIG_PREFIX="$IMAGES_DIR/rootfs" install -C $BUILD_DIR/busybox-1.31.1
cp -v $BUILD_DIR/busybox-1.31.1/examples/depmod.pl $TOOLS_DIR/bin
rm -rf $BUILD_DIR/busybox-1.31.1

step "[2/] Generate Root File System"
# Remove 'linuxrc' which is used when we boot in 'RAM disk' mode.
rm -fv $IMAGES_DIR/rootfs/linuxrc
mkdir -pv $IMAGES_DIR/rootfs/{dev,etc/msg,lib,mnt,proc,root,sys,tmp,var/log}

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
#          +-- /etc/03_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/04_bootscript.sh
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

echo -e "Welcome to \\e[1mMinimal \\e[32mLinux \\e[31mLive\\e[0m (/init)"

# Let's mount all core file systems.
/etc/01_prepare.sh

# Print first message on screen.
cat /etc/msg/init_01.txt

# Wait 5 second or until any keybord key is pressed.
read -t 5 -n1 -s key

if [ ! "$key" = "" ] ; then
  # Print second message on screen.
  cat /etc/msg/init_02.txt

  # Set flag which indicates that we have obtained controlling terminal.
  export PID1_SHELL=true

  # Interactive shell with controlling tty as PID 1.
  exec setsid cttyhack sh
fi

# Create new mountpoint in RAM, make it our new root location and overlay it
# with our storage area (if overlay area exists at all). This operation invokes
# the script '/etc/03_init.sh' as the new init process.
exec /etc/02_overlay.sh

echo "(/init) - you can never see this unless there is a serious bug."

# Wait until any key has been pressed.
read -n1 -s
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
#          +-- /etc/03_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/04_bootscript.sh
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

# Create /etc/02_overlay.sh
cat > $IMAGES_DIR/rootfs/etc/02_overlay.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh (this file)
#          |
#          +-- /etc/03_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/04_bootscript.sh
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

# Create the new mountpoint in RAM.
mount -t tmpfs none /mnt

# Create folders for all critical file systems.
mkdir /mnt/dev
mkdir /mnt/sys
mkdir /mnt/proc
mkdir /mnt/tmp
echo "Created folders for all critical file systems."

# Copy root folders in the new mountpoint.
echo -e "Copying the root file system to \\e[94m/mnt\\e[0m."
for dir in */ ; do
  case $dir in
    dev/)
      # skip
      ;;
    proc/)
      # skip
      ;;
    sys/)
      # skip
      ;;
    mnt/)
      # skip
      ;;
    tmp/)
      # skip
      ;;
    *)
      cp -a $dir /mnt
      ;;
  esac
done

DEFAULT_OVERLAY_DIR="/tmp/minimal/overlay"
DEFAULT_UPPER_DIR="/tmp/minimal/rootfs"
DEFAULT_WORK_DIR="/tmp/minimal/work"

echo "Searching available devices for overlay content."
for DEVICE in /dev/* ; do
  DEV=$(echo "${DEVICE##*/}")
  SYSDEV=$(echo "/sys/class/block/$DEV")

  case $DEV in
    *loop*) continue ;;
  esac

  if [ ! -d "$SYSDEV" ] ; then
    continue
  fi

  mkdir -p /tmp/mnt/device
  DEVICE_MNT=/tmp/mnt/device

  OVERLAY_DIR=""
  OVERLAY_MNT=""
  UPPER_DIR=""
  WORK_DIR=""

  mount $DEVICE $DEVICE_MNT 2>/dev/null
  if [ -d $DEVICE_MNT/minimal/rootfs -a -d $DEVICE_MNT/minimal/work ] ; then
    # folder
    echo -e "  Found \\e[94m/minimal\\e[0m folder on device \\e[31m$DEVICE\\e[0m."
    touch $DEVICE_MNT/minimal/rootfs/minimal.pid 2>/dev/null
    if [ -f $DEVICE_MNT/minimal/rootfs/minimal.pid ] ; then
      # read/write mode
      echo -e "  Device \\e[31m$DEVICE\\e[0m is mounted in read/write mode."

      rm -f $DEVICE_MNT/minimal/rootfs/minimal.pid

      OVERLAY_DIR=$DEFAULT_OVERLAY_DIR
      OVERLAY_MNT=$DEVICE_MNT
      UPPER_DIR=$DEVICE_MNT/minimal/rootfs
      WORK_DIR=$DEVICE_MNT/minimal/work
    else
      # read only mode
      echo -e "  Device \\e[31m$DEVICE\\e[0m is mounted in read only mode."

      OVERLAY_DIR=$DEVICE_MNT/minimal/rootfs
      OVERLAY_MNT=$DEVICE_MNT
      UPPER_DIR=$DEFAULT_UPPER_DIR
      WORK_DIR=$DEFAULT_WORK_DIR
    fi
  elif [ -f $DEVICE_MNT/minimal.img ] ; then
    #image
    echo -e "  Found \\e[94m/minimal.img\\e[0m image on device \\e[31m$DEVICE\\e[0m."

    mkdir -p /tmp/mnt/image
    IMAGE_MNT=/tmp/mnt/image

    LOOP_DEVICE=$(losetup -f)
    losetup $LOOP_DEVICE $DEVICE_MNT/minimal.img

    mount $LOOP_DEVICE $IMAGE_MNT
    if [ -d $IMAGE_MNT/rootfs -a -d $IMAGE_MNT/work ] ; then
      touch $IMAGE_MNT/rootfs/minimal.pid 2>/dev/null
      if [ -f $IMAGE_MNT/rootfs/minimal.pid ] ; then
        # read/write mode
        echo -e "  Image \\e[94m$DEVICE/minimal.img\\e[0m is mounted in read/write mode."

        rm -f $IMAGE_MNT/rootfs/minimal.pid

        OVERLAY_DIR=$DEFAULT_OVERLAY_DIR
        OVERLAY_MNT=$IMAGE_MNT
        UPPER_DIR=$IMAGE_MNT/rootfs
        WORK_DIR=$IMAGE_MNT/work
      else
        # read only mode
        echo -e "  Image \\e[94m$DEVICE/minimal.img\\e[0m is mounted in read only mode."

        OVERLAY_DIR=$IMAGE_MNT/rootfs
        OVERLAY_MNT=$IMAGE_MNT
        UPPER_DIR=$DEFAULT_UPPER_DIR
        WORK_DIR=$DEFAULT_WORK_DIR
      fi
    else
      umount $IMAGE_MNT
      rm -rf $IMAGE_MNT
    fi
  fi

  if [ "$OVERLAY_DIR" != "" -a "$UPPER_DIR" != "" -a "$WORK_DIR" != "" ] ; then
    mkdir -p $OVERLAY_DIR
    mkdir -p $UPPER_DIR
    mkdir -p $WORK_DIR

    mount -t overlay -o lowerdir=$OVERLAY_DIR:/mnt,upperdir=$UPPER_DIR,workdir=$WORK_DIR none /mnt 2>/dev/null

    OUT=$?
    if [ ! "$OUT" = "0" ] ; then
      echo -e "  \\e[31mMount failed (probably on vfat).\\e[0m"

      umount $OVERLAY_MNT 2>/dev/null
      rmdir $OVERLAY_MNT 2>/dev/null

      rmdir $DEFAULT_OVERLAY_DIR 2>/dev/null
      rmdir $DEFAULT_UPPER_DIR 2>/dev/null
      rmdir $DEFAULT_WORK_DIR 2>/dev/null
    else
      # All done, time to go.
      echo -e "  Overlay data from device \\e[31m$DEVICE\\e[0m has been merged."
      break
    fi
  else
    echo -e "  Device \\e[31m$DEVICE\\e[0m has no proper overlay structure."
  fi

  umount $DEVICE_MNT 2>/dev/null
  rm -rf $DEVICE_MNT 2>/dev/null
done

# Move critical file systems to the new mountpoint.
mount --move /dev /mnt/dev
mount --move /sys /mnt/sys
mount --move /proc /mnt/proc
mount --move /tmp /mnt/tmp
echo -e "Mount locations \\e[94m/dev\\e[0m, \\e[94m/sys\\e[0m, \\e[94m/tmp\\e[0m and \\e[94m/proc\\e[0m have been moved to \\e[94m/mnt\\e[0m."

# The new mountpoint becomes file system root. All original root folders are
# deleted automatically as part of the command execution. The '/sbin/init'
# process is invoked and it becomes the new PID 1 parent process.
echo "Switching from initramfs root area to overlayfs root area."
exec switch_root /mnt /etc/03_init.sh

echo "(/etc/02_overlay.sh) - there is a serious bug."

# Wait until any key has been pressed.
read -n1 -s
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/02_overlay.sh

# Create /etc/03_init.sh
cat > $IMAGES_DIR/rootfs/etc/03_init.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/03_init.sh (this file)
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/04_bootscript.sh
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

# Print first message on screen.
cat /etc/msg/03_init_01.txt

# Wait 5 second or until any keybord key is pressed.
read -t 5 -n1 -s key

if [ "$key" = "" ] ; then
  # Use default initialization logic based on configuration in '/etc/inittab'.
  echo -e "Executing \\e[32m/sbin/init\\e[0m as PID 1."
  exec /sbin/init
else
  # Print second message on screen.
  cat /etc/msg/03_init_02.txt

  if [ "$PID1_SHELL" = "true" ] ; then
    # PID1_SHELL flag is set which means we have controlling terminal.
    unset PID1_SHELL
    exec sh
  else
    # Interactive shell with controlling tty as PID 1.
    exec setsid cttyhack sh
  fi
fi

echo "(/etc/03_init.sh) - there is a serious bug."

# Wait until any key has been pressed.
read -n1 -s
EOF
chmod 755 -v $IMAGES_DIR/rootfs/etc/03_init.sh

# Create /etc/04_bootscript.sh
cat > $IMAGES_DIR/rootfs/etc/04_bootscript.sh << "EOF"
#!/bin/sh

# System initialization sequence:
#
# /init
#  |
#  +--(1) /etc/01_prepare.sh
#  |
#  +--(2) /etc/02_overlay.sh
#          |
#          +-- /etc/03_init.sh
#               |
#               +-- /sbin/init
#                    |
#                    +--(1) /etc/04_bootscript.sh (this file)
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

echo -e "Welcome to \\e[1mMinimal \\e[32mLinux \\e[31mLive\\e[0m (/sbin/init)"

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
chmod 755 -v $IMAGES_DIR/rootfs/etc/04_bootscript.sh

# Create /etc/inittab
cat > $IMAGES_DIR/rootfs/etc/inittab << "EOF"
::sysinit:/etc/04_bootscript.sh
::restart:/sbin/init
::shutdown:echo -e "\nSyncing all file buffers."
::shutdown:sync
::shutdown:echo "Unmounting all filesystems."
::shutdown:umount -a -r
::shutdown:echo -e "\n  \\e[1mCome back soon. :)\\e[0m\n"
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

# /etc/motd
cat > $IMAGES_DIR/rootfs/etc/motd << "EOF"
[0m
  ###################################
  #                                 #
  #  Welcome to [1mMinimal [32mLinux [31mLive[0m  #
  #                                 #
  ###################################
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/motd

# Create /etc/msg/03_init_01.txt
cat > $IMAGES_DIR/rootfs/etc/msg/03_init_01.txt << "EOF"
[1m
  Press empty key (TAB, SPACE, ENTER) or wait 5 seconds to continue with the
  system initialization process. Press any other key for PID 1 rescue shell
  outside of the initramfs area.
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/msg/03_init_01.txt

# Create /etc/msg/03_init_02.txt
cat > $IMAGES_DIR/rootfs/etc/msg/03_init_02.txt << "EOF"
[1m  This is PID 1 rescue shell outside of the initramfs area. Execute the
  following in order to continue with the system initialization:
[1m[32m
  exec /sbin/init
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/msg/03_init_02.txt

# Create /etc/msg/init_01.txt
cat > $IMAGES_DIR/rootfs/etc/msg/init_01.txt << "EOF"
[1m
  Press empty key (TAB, SPACE, ENTER) or wait 5 seconds to continue with the
  overlay initialization process. Press any other key for PID 1 rescue shell
  inside the initramfs area.
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/msg/init_01.txt

# Create /etc/msg/init_02.txt
cat > $IMAGES_DIR/rootfs/etc/msg/init_02.txt << "EOF"
[1m  This is PID 1 rescue shell inside the initramfs area. Execute the following in
  order to continue with the overlay initialization process:
[1m[32m
  exec /etc/02_overlay.sh
[0m[1m
  Execute the following in order to skip the overlay initialization and continue
  directly with the system initialization:
[1m[32m
  exec /sbin/init
[0m
EOF
chmod 644 -v $IMAGES_DIR/rootfs/etc/msg/init_02.txt

# Create /var/log/{btmp,lastlog,messages,utmp,wtmp}
touch $IMAGES_DIR/rootfs/var/log/{btmp,lastlog,messages,utmp,wtmp}
chmod 644 -v $IMAGES_DIR/rootfs/var/log/{btmp,lastlog,messages,utmp,wtmp}

step "[3/] Pack Root File System"
( cd $IMAGES_DIR/rootfs && find . | cpio -R root:root -H newc -o | xz -9 --check=none > $IMAGES_DIR/rootfs.cpio.xz )

step "[4/] ISO Overlay Structure"
mkdir -p $IMAGES_DIR/isoimage/minimal/rootfs
mkdir -p $IMAGES_DIR/isoimage/minimal/work
touch $IMAGES_DIR/isoimage/minimal/rootfs/QNAS_README

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
mkdir -pv $IMAGES_DIR/uefi/minimal/x86_64
cp -v $KERNEL_DIR/bzImage $IMAGES_DIR/uefi/minimal/x86_64/kernel.xz
cp -v $IMAGES_DIR/rootfs.cpio.xz $IMAGES_DIR/uefi/minimal/x86_64/rootfs.xz
step "Copy 'systemd-boot' UEFI Boot Loader"
mkdir -pv $IMAGES_DIR/uefi/EFI/BOOT
cp -v $SUPPORT_DIR/systemd-boot/BOOTx64.EFI $IMAGES_DIR/uefi/EFI/BOOT
step "'systemd-boot' Configuration"
mkdir -pv $IMAGES_DIR/uefi/loader/entries
cat > $IMAGES_DIR/uefi/loader/loader.conf << "EOF"
default mll-x86_64
timeout 5
editor 1
EOF
cat > $IMAGES_DIR/uefi/loader/entries/mll-x86_64.conf << "EOF"
title Minimal Linux Live
version x86_64
efi /minimal/x86_64/kernel.xz
options initrd=/minimal/x86_64/rootfs.xz
EOF
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/loader ::loader
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/EFI ::EFI
mcopy -bsp -i $IMAGES_DIR/uefi.img $IMAGES_DIR/uefi/minimal ::minimal

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
  -o $IMAGES_DIR/minimal_linux_live.iso \
  $IMAGES_DIR/isoimage

success "\nTotal QNAS image generate time: $(timer $total_build_time)\n"
