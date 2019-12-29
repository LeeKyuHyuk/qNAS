#!/bin/bash
#
# QNAS toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022
export LC_ALL=POSIX

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
}

function check_tarballs {
  LIST_OF_TARBALLS="
  linux-5.4.6.tar.xz
  "

  for tarball in $LIST_OF_TARBALLS ; do
    if ! [[ -f $SOURCES_DIR/$tarball ]] ; then
      error "Can't find '$tarball'!"
      exit 1
    fi
  done
}

function do_strip {
  set +o errexit
  if [[ $CONFIG_STRIP_AND_DELETE_DOCS = 1 ]] ; then
    strip --strip-debug $TOOLS_DIR/lib/*
    strip --strip-unneeded $TOOLS_DIR/{,s}bin/*
    rm -rf $TOOLS_DIR/{,share}/{info,man,doc}
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
check_tarballs
total_build_time=$(timer)

rm -rf $BUILD_DIR $KERNEL_DIR/bzImage
mkdir -pv $BUILD_DIR $KERNEL_DIR

step "[1/1] Linux Kernel 5.4.6"
extract $SOURCES_DIR/linux-5.4.6.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-5.4.6
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH $CONFIG_LINUX_KERNEL_DEFCONFIG -C $BUILD_DIR/linux-5.4.6
# Changes the name of the system to 'minimal'.
sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"$CONFIG_HOSTNAME\"/" $BUILD_DIR/linux-5.4.6/.config
# Enable overlay support, e.g. merge ro and rw directories (3.18+).
sed -i "s/.*CONFIG_OVERLAY_FS.*/CONFIG_OVERLAY_FS=y/" $BUILD_DIR/linux-5.4.6/.config
# Enable overlayfs redirection (4.10+).
echo "CONFIG_OVERLAY_FS_REDIRECT_DIR=y" >> $BUILD_DIR/linux-5.4.6/.config
# Turn on inodes index feature by default (4.13+).
echo "CONFIG_OVERLAY_FS_INDEX=y" >> $BUILD_DIR/linux-5.4.6/.config
# Follow redirects even if redirects are turned off (4.15+).
echo "CONFIG_OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW=y" >> $BUILD_DIR/linux-5.4.6/.config
# Turn on NFS export feature by default (4.16+).
echo "CONFIG_OVERLAY_FS_NFS_EXPORT=y" >> $BUILD_DIR/linux-5.4.6/.config
# Auto enable inode number mapping (4.17+).
echo "CONFIG_OVERLAY_FS_XINO_AUTO=y" >> $BUILD_DIR/linux-5.4.6/.config
# Тurn on metadata only copy up feature by default (4.19+).
echo "CONFIG_OVERLAY_FS_METACOPY=y" >> $BUILD_DIR/linux-5.4.6/.config
# Step 1 - disable all active kernel compression options (should be only one).
sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" $BUILD_DIR/linux-5.4.6/.config
# Step 2 - enable the 'xz' compression option.
sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" $BUILD_DIR/linux-5.4.6/.config
# Enable the VESA framebuffer for graphics support.
sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" $BUILD_DIR/linux-5.4.6/.config
# Disable debug symbols in kernel => smaller kernel binary.
sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" $BUILD_DIR/linux-5.4.6/.config
# Enable the EFI stub
sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" $BUILD_DIR/linux-5.4.6/.config
# Request that the firmware clear the contents of RAM after reboot (4.14+).
echo "CONFIG_RESET_ATTACK_MITIGATION=y" >> $BUILD_DIR/linux-5.4.6/.config
# Disable Apple Properties (Useful for Macs but useless in general)
echo "CONFIG_APPLE_PROPERTIES=n" >> $BUILD_DIR/linux-5.4.6/.config
echo "CONFIG_EFI_MIXED=y" >> $BUILD_DIR/linux-5.4.6/.config
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH HOSTCC="gcc -O2 -I$TOOLS_DIR/include -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/linux-5.4.6 bzImage
cp $BUILD_DIR/linux-5.4.6/arch/x86/boot/bzImage $KERNEL_DIR/bzImage
rm -rf $BUILD_DIR/linux-5.4.6

success "\nTotal kernel build time: $(timer $total_build_time)\n"
