#!/bin/bash
#
# QNAS toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export CFLAGS="-O2 -I$TOOLS_DIR/include"
export CPPFLAGS="-O2 -I$TOOLS_DIR/include"
export CXXFLAGS="-O2 -I$TOOLS_DIR/include"
export LDFLAGS="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib"

export LC_ALL=POSIX
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export PKG_CONFIG="$TOOLS_DIR/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_LIBDIR="$TOOLS_DIR/lib/pkgconfig:$TOOLS_DIR/share/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_PKG_VERSION="QNAS x86_64 2019.12"
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
}

function check_tarballs {
    LIST_OF_TARBALLS="

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

step "[1/25] Create toolchain directory."
rm -rf $BUILD_DIR $TOOLS_DIR
mkdir -pv $BUILD_DIR $TOOLS_DIR
ln -svf . $TOOLS_DIR/usr

step "[2/25] Create the sysroot directory"
mkdir -pv $SYSROOT_DIR
ln -svf . $SYSROOT_DIR/usr
mkdir -pv $SYSROOT_DIR/lib
if [[ "$CONFIG_LINUX_ARCH" = "i386" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "x86_64" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib64
fi

step "[4/25] Pkgconf 1.6.1"
extract $SOURCES_DIR/pkgconf-1.6.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/pkgconf-1.6.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-dependency-tracking )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkgconf-1.6.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/pkgconf-1.6.3
install -m 0755 -D $SUPPORT_DIR/pkgconf/pkg-config $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STAGING_SUBDIR@,$SYSROOT_DIR,g" $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STATIC@,," $TOOLS_DIR/bin/pkg-config
rm -rf $BUILD_DIR/pkgconf-1.6.3

step "[9/25] M4 1.4.18"
extract $SOURCES_DIR/m4-1.4.18.tar.xz $BUILD_DIR
patch -Np1 -i $SUPPORT_DIR/m4/fflush-adjust-to-glibc-2.28-libio.h-removal.patch -d $BUILD_DIR/m4-1.4.18
patch -Np1 -i $SUPPORT_DIR/m4/fflush-be-more-paranoid-about-libio.h-change.patch -d $BUILD_DIR/m4-1.4.18
( cd $BUILD_DIR/m4-1.4.18 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4-1.4.18
make -j$PARALLEL_JOBS install -C $BUILD_DIR/m4-1.4.18
rm -rf $BUILD_DIR/m4-1.4.18

step "[9/25] Libtool 2.4.6"
extract $SOURCES_DIR/libtool-2.4.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool-2.4.6 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool-2.4.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libtool-2.4.6
rm -rf $BUILD_DIR/libtool-2.4.6

step "[9/25] Autoconf 2.69"
extract $SOURCES_DIR/autoconf-2.69.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf-2.69 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf-2.69
make -j$PARALLEL_JOBS install -C $BUILD_DIR/autoconf-2.69
rm -rf $BUILD_DIR/autoconf-2.69

step "[9/25] Automake 1.16.1"
extract $SOURCES_DIR/automake-1.16.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake-1.16.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake-1.16.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/automake-1.16.1
mkdir -p $SYSROOT_DIR/usr/share/aclocal
rm -rf $BUILD_DIR/automake-1.16.1

step "[12/25] Zlib 1.2.11"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11 && ./configure --prefix=$TOOLS_DIR )
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "[9/25] Util-linux 2.34"
extract $SOURCES_DIR/util-linux-2.34.tar.xz $BUILD_DIR
( cd $BUILD_DIR/util-linux-2.34 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-python \
    --enable-libblkid \
    --enable-libmount \
    --enable-libuuid \
    --without-ncurses \
    --without-ncursesw \
    --without-tinfo \
    --disable-makeinstall-chown \
    --disable-agetty \
    --disable-chfn-chsh \
    --disable-chmem \
    --disable-login \
    --disable-lslogins \
    --disable-mesg \
    --disable-more \
    --disable-newgrp \
    --disable-nologin \
    --disable-nsenter \
    --disable-pg \
    --disable-rfkill \
    --disable-schedutils \
    --disable-setpriv \
    --disable-setterm \
    --disable-su \
    --disable-sulogin \
    --disable-tunelp \
    --disable-ul \
    --disable-unshare \
    --disable-uuidd \
    --disable-vipw \
    --disable-wall \
    --disable-wdctl \
    --disable-write \
    --disable-zramctl )
make -j$PARALLEL_JOBS -C $BUILD_DIR/util-linux-2.34
make -j$PARALLEL_JOBS install -C $BUILD_DIR/util-linux-2.34
rm -rf $BUILD_DIR/util-linux-2.34

step "[9/25] E2fsprogs 1.45.4"
extract $SOURCES_DIR/e2fsprogs-1.45.4.tar.gz $BUILD_DIR
( cd $BUILD_DIR/e2fsprogs-1.45.4 && \
    ac_cv_path_LDCONFIG=true \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-defrag \
    --disable-e2initrd-helper \
    --disable-fuse2fs \
    --disable-libblkid \
    --disable-libuuid \
    --disable-testio-debug \
    --enable-symlink-install \
    --enable-elf-shlibs \
    --with-crond-dir=no )
make -j$PARALLEL_JOBS -C $BUILD_DIR/e2fsprogs-1.45.4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/e2fsprogs-1.45.4
rm -rf $BUILD_DIR/e2fsprogs-1.45.4

step "[9/25] Fakeroot 1.24"
extract $SOURCES_DIR/fakeroot_1.24.orig.tar.gz $BUILD_DIR
( cd $BUILD_DIR/fakeroot-1.24 && \
    ac_cv_header_sys_capability_h=no \
    ac_cv_func_capset=no \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/fakeroot-1.24
make -j$PARALLEL_JOBS install -C $BUILD_DIR/fakeroot-1.24
rm -rf $BUILD_DIR/fakeroot-1.24

step "[9/25] Makedevs"
gcc -O2 -I$TOOLS_DIR/include $SUPPORT_DIR/makedevs/makedevs.c -o $TOOLS_DIR/bin/makedevs -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib

step "[9/25] Mkpasswd 5.0.26"
gcc -O2 -I$TOOLS_DIR/include -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib $SUPPORT_DIR/mkpasswd/mkpasswd.c $SUPPORT_DIR/mkpasswd/utils.c -o $TOOLS_DIR/bin/mkpasswd -lcrypt

step "[9/25] Bison 3.5"
extract $SOURCES_DIR/bison-3.5.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bison-3.5 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison-3.5
make -j$PARALLEL_JOBS install -C $BUILD_DIR/bison-3.5
rm -rf $BUILD_DIR/bison-3.5

step "[9/25] Gawk 5.0.1"
extract $SOURCES_DIR/gawk-5.0.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gawk-5.0.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-readline \
    --without-mpfr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.0.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gawk-5.0.1
rm -rf $BUILD_DIR/gawk-5.0.1

step "[4/25] Binutils 2.33.1"
extract $SOURCES_DIR/binutils-2.33.1.tar.xz $BUILD_DIR
mkdir -pv $BUILD_DIR/binutils-2.33.1/binutils-build
( cd $BUILD_DIR/binutils-2.33.1/binutils-build && \
    MAKEINFO=true \
    $BUILD_DIR/binutils-2.33.1/configure \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --disable-multilib \
    --disable-werror \
    --disable-shared \
    --enable-static \
    --with-sysroot=$SYSROOT_DIR \
    --enable-poison-system-directories \
    --disable-sim \
    --disable-gdb )
make -j$PARALLEL_JOBS configure-host -C $BUILD_DIR/binutils-2.33.1/binutils-build
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils-2.33.1/binutils-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/binutils-2.33.1/binutils-build
rm -rf $BUILD_DIR/binutils-2.33.1

step "[5/25] Gcc 9.2.0 - Static"
tar -Jxf $SOURCES_DIR/gcc-9.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.1.2.tar.xz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/gmp-6.1.2 $BUILD_DIR/gcc-9.2.0/gmp
extract $SOURCES_DIR/mpfr-4.0.2.tar.xz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/mpfr-4.0.2 $BUILD_DIR/gcc-9.2.0/mpfr
extract $SOURCES_DIR/mpc-1.1.0.tar.gz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/mpc-1.1.0 $BUILD_DIR/gcc-9.2.0/mpc
mkdir -pv $BUILD_DIR/gcc-9.2.0/gcc-build
( cd $BUILD_DIR/gcc-9.2.0/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-9.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --enable-libquadmath \
    --enable-tls \
    --enable-threads \
    --without-isl \
    --without-cloog \
    --with-arch="nocona" \
    --enable-languages=c \
    --disable-shared \
    --without-headers \
    --disable-threads \
    --with-newlib \
    --disable-largefile \
    --disable-static )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes all-gcc all-target-libgcc -C $BUILD_DIR/gcc-9.2.0/gcc-build
make -j$PARALLEL_JOBS install-gcc install-target-libgcc -C $BUILD_DIR/gcc-9.2.0/gcc-build
rm -rf $BUILD_DIR/gcc-9.2.0

step "[3/25] Linux 5.4.6 API Headers"
extract $SOURCES_DIR/linux-5.4.6.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-5.4.6
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH headers_check -C $BUILD_DIR/linux-5.4.6
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR headers_install -C $BUILD_DIR/linux-5.4.6
rm -rf $BUILD_DIR/linux-5.4.6

step "[9/25] glibc 2.30"
extract $SOURCES_DIR/glibc-2.30.tar.xz $BUILD_DIR
mkdir $BUILD_DIR/glibc-2.30/glibc-build
( cd $BUILD_DIR/glibc-2.30/glibc-build && \
    CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
    CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++" \
    AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar" \
    AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as" \
    LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" \
    RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib" \
    READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf" \
    STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip" \
    CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="-O2 " LDFLAGS="" \
    ac_cv_path_BASH_SHELL=/bin/sh \
    libc_cv_forced_unwind=yes \
    libc_cv_ssp=no \
    $BUILD_DIR/glibc-2.30/configure \
    --target=$CONFIG_TARGET \
    --host=$CONFIG_TARGET \
    --build=$CONFIG_HOST \
    --prefix=/usr \
    --enable-shared \
    --enable-lock-elision \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --without-cvs \
    --disable-profile \
    --without-gd \
    --enable-obsolete-rpc \
    --enable-kernel=5.4.6 \
    --with-headers=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc-2.30/glibc-build
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc-2.30/glibc-build
rm -rf $BUILD_DIR/glibc-2.30

step "[7/25] Gcc 9.2.0 - Final"
tar -Jxf $SOURCES_DIR/gcc-9.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.1.2.tar.xz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/gmp-6.1.2 $BUILD_DIR/gcc-9.2.0/gmp
extract $SOURCES_DIR/mpfr-4.0.2.tar.xz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/mpfr-4.0.2 $BUILD_DIR/gcc-9.2.0/mpfr
extract $SOURCES_DIR/mpc-1.1.0.tar.gz $BUILD_DIR/gcc-9.2.0
mv -v $BUILD_DIR/gcc-9.2.0/mpc-1.1.0 $BUILD_DIR/gcc-9.2.0/mpc
mkdir -v $BUILD_DIR/gcc-9.2.0/gcc-build
( cd $BUILD_DIR/gcc-9.2.0/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-9.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --enable-libquadmath \
    --enable-tls \
    --enable-threads \
    --without-isl \
    --without-cloog \
    --with-arch="nocona" \
    --enable-languages=c \
    --with-build-time-tools=$TOOLS_DIR/$CONFIG_TARGET/bin \
    --enable-shared \
    --disable-libgomp \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-pkgversion="$CONFIG_PKG_VERSION" )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes -C $BUILD_DIR/gcc-9.2.0/gcc-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gcc-9.2.0/gcc-build
if [ ! -e $TOOLS_DIR/bin/$CONFIG_TARGET-cc ]; then
    ln -vf $TOOLS_DIR/bin/$CONFIG_TARGET-gcc $TOOLS_DIR/bin/$CONFIG_TARGET-cc
fi
rm -rf $BUILD_DIR/gcc-9.2.0

step "[14/25] Elfutils 0.178"
extract $SOURCES_DIR/elfutils-0.178.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/elfutils-0.178 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-debuginfod )
make -j$PARALLEL_JOBS -C $BUILD_DIR/elfutils-0.178
make -j$PARALLEL_JOBS install -C $BUILD_DIR/elfutils-0.178
rm -rf $BUILD_DIR/elfutils-0.178

step "[9/25] Dosfstools 4.1"
extract $SOURCES_DIR/dosfstools-4.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/dosfstools-4.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --enable-compat-symlinks )
make -j$PARALLEL_JOBS -C $BUILD_DIR/dosfstools-4.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/dosfstools-4.1
rm -rf $BUILD_DIR/dosfstools-4.1

step "[9/25] libconfuse 3.2.2"
extract $SOURCES_DIR/confuse-3.2.2.tar.xz $BUILD_DIR
( cd $BUILD_DIR/confuse-3.2.2 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/confuse-3.2.2
make -j$PARALLEL_JOBS install -C $BUILD_DIR/confuse-3.2.2
rm -rf $BUILD_DIR/confuse-3.2.2

step "[9/25] Genimage 11"
extract $SOURCES_DIR/genimage-11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/genimage-11 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/genimage-11
make -j$PARALLEL_JOBS install -C $BUILD_DIR/genimage-11
rm -rf $BUILD_DIR/genimage-11

step "[11/25] Flex 2.6.4"
extract $SOURCES_DIR/flex-2.6.4.tar.gz $BUILD_DIR
( cd $BUILD_DIR/flex-2.6.4 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j$PARALLEL_JOBS -C $BUILD_DIR/flex-2.6.4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/flex-2.6.4
rm -rf $BUILD_DIR/flex-2.6.4

step "[11/25] Mtools 4.0.23"
extract $SOURCES_DIR/mtools-4.0.23.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/mtools-4.0.23 && \
    ac_cv_lib_bsd_gethostbyname=no \
    ac_cv_lib_bsd_main=no \
    ac_cv_path_INSTALL_INFO= \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j1 -C $BUILD_DIR/mtools-4.0.23
make -j1 install -C $BUILD_DIR/mtools-4.0.23
rm -rf $BUILD_DIR/mtools-4.0.23

step "[13/25] Openssl 1.1.1d"
extract $SOURCES_DIR/openssl-1.1.1d.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl-1.1.1d && \
    ./config \
    --prefix=$TOOLS_DIR \
    --openssldir=$TOOLS_DIR/etc/ssl \
    --libdir=lib \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    shared \
    zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1d
make -j$PARALLEL_JOBS install -C $BUILD_DIR/openssl-1.1.1d
rm -rf $BUILD_DIR/openssl-1.1.1d

do_strip

success "\nTotal toolchain build time: $(timer $total_build_time)\n"
