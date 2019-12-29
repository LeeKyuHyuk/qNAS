#!/bin/bash
#
# QNAS system build script
# Optional parameteres below:

set -o nounset
set -o errexit

CONFIG_PKG_VERSION="QNAS x86_64 2019.02"
CONFIG_BUG_URL="https://github.com/LeeKyuHyuk/qnas/issues"

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

function check_tarballs {
  LIST_OF_TARBALLS="
  busybox-1.30.1.tar.bz2
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
    $CONFIG_TARGET-strip --strip-debug $ROOTFS_DIR/lib/*
    $CONFIG_TARGET-strip --strip-unneeded $ROOTFS_DIR/{,s}bin/*
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

export CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc"
export CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++"
export AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar"
export AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as"
export LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld"
export RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib"
export READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf"
export STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip"

export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

rm -rf $BUILD_DIR $ROOTFS_DIR
mkdir -pv $BUILD_DIR $ROOTFS_DIR

step "[1/2] Create root file system directory."
mkdir -pv $ROOTFS_DIR/{boot,bin,dev,etc,lib,media,mnt,opt,proc,root,run,sbin,src,sys,tmp,usr}
chmod -v 1777 $ROOTFS_DIR/tmp
mkdir -pv $ROOTFS_DIR/dev/{pts,shm}
ln -svf /proc/self/fd $ROOTFS_DIR/dev/fd
ln -svf /proc/self/fd/2 $ROOTFS_DIR/dev/stderr
ln -svf /proc/self/fd/0 $ROOTFS_DIR/dev/stdin
ln -svf /proc/self/fd/1 $ROOTFS_DIR/dev/stdout
ln -svf /tmp/log $ROOTFS_DIR/dev/log
mkdir -pv $ROOTFS_DIR/etc/{network,profile.d}
cp -v $SUPPORT_DIR/skeleton/etc/{fstab,group,hosts,passwd,profile,protocols,services,shadow} $ROOTFS_DIR/etc/
sed -i -e s,^root:[^:]*:,root:"`$TOOLS_DIR/bin/mkpasswd -m "sha-512" "$CONFIG_ROOT_PASSWD"`":, $ROOTFS_DIR/etc/shadow
mkdir -pv $ROOTFS_DIR/etc/network/{if-down.d,if-post-down.d,if-pre-up.d,if-up.d}
cp -v $SUPPORT_DIR/skeleton/etc/profile.d/umask.sh $ROOTFS_DIR/etc/profile.d/umask.sh
ln -svf /proc/self/mounts $ROOTFS_DIR/etc/mtab
ln -svf /tmp/resolv.conf $ROOTFS_DIR/etc/resolv.conf
mkdir -pv $ROOTFS_DIR/usr/{bin,lib,sbin}
mkdir -pv $ROOTFS_DIR/var/lib
ln -svf /tmp $ROOTFS_DIR/var/cache
ln -svf /tmp $ROOTFS_DIR/var/lock
ln -svf /tmp $ROOTFS_DIR/var/log
ln -svf /tmp $ROOTFS_DIR/var/run
ln -svf /tmp $ROOTFS_DIR/var/spool
ln -svf /tmp $ROOTFS_DIR/var/tmp
ln -svf /tmp $ROOTFS_DIR/var/lib/misc
if [ "$CONFIG_LINUX_ARCH" = "i386" ] ; then \
  ln -snvf lib $ROOTFS_DIR/lib32 ; \
  ln -snvf lib $ROOTFS_DIR/usr/lib32 ; \
fi;
if [ "$CONFIG_LINUX_ARCH" = "x86_64" ] ; then \
  ln -snvf lib $ROOTFS_DIR/lib64 ; \
  ln -snvf lib $ROOTFS_DIR/usr/lib64 ; \
fi;

step "Setting Data Partition Mount Point"
mkdir -pv $ROOTFS_DIR/data
echo "/dev/sda3		/data		ext2	defaults	0	0" >> $ROOTFS_DIR/etc/fstab

step "copy gcc lib"
cp -v $TOOLS_DIR/$CONFIG_TARGET/lib64/libgcc_s* $ROOTFS_DIR/lib/
cp -v $TOOLS_DIR/$CONFIG_TARGET/lib64/libatomic* $ROOTFS_DIR/lib/

step "[6/13] Musl 1.1.21"
extract $SOURCES_DIR/musl-1.1.21.tar.gz $BUILD_DIR
( cd $BUILD_DIR/musl-1.1.21 && \
    ./configure \
    CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" \
    --prefix=/ \
    --target=$CONFIG_TARGET )
make -j$PARALLEL_JOBS -C $BUILD_DIR/musl-1.1.21
DESTDIR=$ROOTFS_DIR make -j$PARALLEL_JOBS install-libs -C $BUILD_DIR/musl-1.1.21
rm -rf $BUILD_DIR/musl-1.1.21

step "[2/2] Busybox 1.30.1"
extract $SOURCES_DIR/busybox-1.30.1.tar.bz2 $BUILD_DIR
make -j$PARALLEL_JOBS distclean -C $BUILD_DIR/busybox-1.30.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" defconfig -C $BUILD_DIR/busybox-1.30.1
# sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" $BUILD_DIR/busybox-1.30.1/.config
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/busybox-1.30.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" CONFIG_PREFIX="$ROOTFS_DIR" install -C $BUILD_DIR/busybox-1.30.1
if grep -q "CONFIG_UDHCPC=y" $BUILD_DIR/busybox-1.30.1/.config; then
  install -m 0755 -Dv $SUPPORT_DIR/skeleton/usr/share/udhcpc/default.script $ROOTFS_DIR/usr/share/udhcpc/default.script
  install -m 0755 -dv $ROOTFS_DIR/usr/share/udhcpc/default.script.d
fi
if grep -q "CONFIG_SYSLOGD=y" $BUILD_DIR/busybox-1.30.1/.config; then
  install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/S01logging $ROOTFS_DIR/etc/init.d/S01logging
else
  rm -fv $ROOTFS_DIR/etc/init.d/S01logging
fi
if grep -q "CONFIG_FEATURE_TELNETD_STANDALONE=y" $BUILD_DIR/busybox-1.30.1/.config; then
  install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/S50telnet $ROOTFS_DIR/etc/init.d/S50telnet
fi
install -Dv -m 0644 $SUPPORT_DIR/skeleton/etc/inittab $ROOTFS_DIR/etc/inittab
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/rcK $ROOTFS_DIR/etc/init.d/rcK
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/rcS $ROOTFS_DIR/etc/init.d/rcS
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/S20urandom $ROOTFS_DIR/etc/init.d/S20urandom
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/init.d/S40network $ROOTFS_DIR/etc/init.d/S40network
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/network/if-pre-up.d/wait_iface $ROOTFS_DIR/etc/network/if-pre-up.d/wait_iface
install -m 0755 -Dv $SUPPORT_DIR/skeleton/etc/network/nfs_check $ROOTFS_DIR/etc/network/nfs_check
cp -v $SUPPORT_DIR/skeleton/etc/network/interfaces $ROOTFS_DIR/etc/network/interfaces
echo "$CONFIG_HOSTNAME" > $ROOTFS_DIR/etc/hostname
echo "127.0.1.1	$CONFIG_HOSTNAME" >> $ROOTFS_DIR/etc/hosts
echo "Welcome to QNAS" > $ROOTFS_DIR/etc/issue
cp -v $BUILD_DIR/busybox-1.30.1/examples/depmod.pl $TOOLS_DIR/bin
rm -rf $BUILD_DIR/busybox-1.30.1

step "Zlib 1.2.11"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11 && ./configure --prefix=/usr )
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 -C $BUILD_DIR/zlib-1.2.11 DESTDIR=$SYSROOT_DIR LDCONFIG=true install
make -j1 -C $BUILD_DIR/zlib-1.2.11 DESTDIR=$ROOTFS_DIR LDCONFIG=true install
rm -rf $BUILD_DIR/zlib-1.2.11

step "vsftpd 3.0.3"
extract $SOURCES_DIR/vsftpd-3.0.3.tar.gz $BUILD_DIR
patch -Np1 -i $SUPPORT_DIR/vsftpd/fix-CVE-2015-1419.patch -d $BUILD_DIR/vsftpd-3.0.3
patch -Np1 -i $SUPPORT_DIR/vsftpd/sysdeputil.c-Fix-with-musl-which-does-not-have-utmpx.patch -d $BUILD_DIR/vsftpd-3.0.3
patch -Np1 -i $SUPPORT_DIR/vsftpd/utmpx-builddef.patch -d $BUILD_DIR/vsftpd-3.0.3
# sed -i -e 's/.*VSF_BUILD_SSL/#define VSF_BUILD_SSL/' $BUILD_DIR/vsftpd-3.0.3/builddefs.h
make -j$PARALLEL_JOBS CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" LDFLAGS="" LIBS="-lcrypt `$TOOLS_DIR/bin/pkg-config --libs libssl libcrypto`" -C $BUILD_DIR/vsftpd-3.0.3
install -D -m 755 $BUILD_DIR/vsftpd-3.0.3/vsftpd $ROOTFS_DIR/usr/sbin/vsftpd
test -f $ROOTFS_DIR/etc/vsftpd.conf || install -D -m 644 $BUILD_DIR/vsftpd-3.0.3/vsftpd.conf $ROOTFS_DIR/etc/vsftpd.conf
install -dv -m 700 $ROOTFS_DIR/usr/share/empty
install -dv -m 555 $ROOTFS_DIR/home/ftp
install -Dv -m 755 $SUPPORT_DIR/vsftpd/S70vsftpd $ROOTFS_DIR/etc/init.d/S70vsftpd
install -Dv -m 755 $SUPPORT_DIR/vsftpd/vsftpd.conf $ROOTFS_DIR/etc/vsftpd.conf
echo "ftp:x:45:45:anonymous_user:/home/ftp:/bin/false" >> $ROOTFS_DIR/etc/passwd
echo "vsftpd:x:47:47:vsftpd:/dev/null:/bin/false" >> $ROOTFS_DIR/etc/passwd
echo "ftp:x:45:" >> $ROOTFS_DIR/etc/group
echo "vsftpd:x:47:" >> $ROOTFS_DIR/etc/group
rm -rf $BUILD_DIR/vsftpd-3.0.3

step "Curl 7.64.1"
extract $SOURCES_DIR/curl-7.64.1.tar.xz $BUILD_DIR
(cd $BUILD_DIR/curl-7.64.1 && \
./configure \
--target=$CONFIG_TARGET \
--host=$CONFIG_TARGET \
--build=$CONFIG_HOST \
--prefix=/usr \
--disable-static \
--enable-threaded-resolver \
--with-ca-path=/etc/ssl/certs )
make -j$PARALLEL_JOBS  -C $BUILD_DIR/curl-7.64.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/curl-7.64.1
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/curl-7.64.1
rm -rf $BUILD_DIR/curl-7.64.1

step "libevent 2.1.8"
extract $SOURCES_DIR/libevent-2.1.8-stable.tar.gz $BUILD_DIR
(cd $BUILD_DIR/libevent-2.1.8-stable && \
./configure \
--target=$CONFIG_TARGET \
--host=$CONFIG_TARGET \
--build=$CONFIG_HOST \
--prefix=/usr \
--disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libevent-2.1.8-stable/
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libevent-2.1.8-stable/
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/libevent-2.1.8-stable/
rm -rf $BUILD_DIR/libevent-2.1.8-stable

step "libopenssl 1.1.1a"
extract $SOURCES_DIR/openssl-1.1.1a.tar.gz $BUILD_DIR
(cd $BUILD_DIR/openssl-1.1.1a && \
./Configure \
linux-x86_64 \
--prefix=/usr \
--openssldir=/etc/ssl \
-latomic \
threads \
shared \
no-rc5 \
enable-camellia \
enable-mdc2 \
no-tests \
no-fuzz-libfuzzer \
no-fuzz-afl \
zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1a
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1a DESTDIR=$SYSROOT_DIR install
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1a DESTDIR=$ROOTFS_DIR install
rm -rf $BUILD_DIR/openssl-1.1.1a

step "Transmission 2.94"
extract $SOURCES_DIR/transmission-2.94.tar.xz $BUILD_DIR
patch -Np1 -i $SUPPORT_DIR/transmission/0001-fix-utypes.patch -d $BUILD_DIR/transmission-2.94
patch -Np1 -i $SUPPORT_DIR/transmission/0002-musl-missing-header.patch -d $BUILD_DIR/transmission-2.94
patch -Np1 -i $SUPPORT_DIR/transmission/0003-fix-utp-include.patch -d $BUILD_DIR/transmission-2.94
(cd $BUILD_DIR/transmission-2.94 && \
LIBEVENT_CFLAGS=-I$SYSROOT_DIR/usr/include \
LIBEVENT_LIBS="-L$SYSROOT_DIR/usr/lib -levent" \
LIBCURL_CFLAGS=-I$SYSROOT_DIR/usr/include \
LIBCURL_LIBS="-L$SYSROOT_DIR/usr/lib -lcurl" \
ZLIB_CFLAGS=-I$SYSROOT_DIR/usr/include \
ZLIB_LIBS="-L$SYSROOT_DIR/usr/lib -lz" \
OPENSSL_CFLAGS=-I$SYSROOT_DIR/usr/include \
OPENSSL_LIBS="-L$SYSROOT_DIR/usr/lib -lssl -lcrypto" \
./configure \
--target=$CONFIG_TARGET \
--host=$CONFIG_TARGET \
--build=$CONFIG_HOST \
--prefix=/usr \
--without-inotify \
--enable-lightweight \
--disable-external-natpmp \
--disable-utp \
--disable-cli \
--enable-daemon \
--without-systemd \
--without-gtk )
make -j$PARALLEL_JOBS -C $BUILD_DIR/transmission-2.94/
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/transmission-2.94/
install -Dv -m 755 $SUPPORT_DIR/transmission/S92transmission $ROOTFS_DIR/etc/init.d/S92transmission
mkdir -pv $ROOTFS_DIR/data/transmission
mkdir -pv $ROOTFS_DIR/var/config/transmission-daemon
cp -v $SUPPORT_DIR/transmission/settings.json $ROOTFS_DIR/var/config/transmission-daemon/settings.json
echo "transmission:x:1001:1001:transmission:/data/transmission:/bin/sh" >> $ROOTFS_DIR/etc/passwd
echo "transmission:x:1001:" >> $ROOTFS_DIR/etc/group
echo "transmission::10933:0:99999:7:::" >> $ROOTFS_DIR/etc/shadow
sed -i -e s,^transmission:[^:]*:,transmission:"`$TOOLS_DIR/bin/mkpasswd -m "sha-512" "transmission"`":, $ROOTFS_DIR/etc/shadow
rm -rf $BUILD_DIR/transmission-2.94

success "\nTotal system build time: $(timer $total_build_time)\n"
