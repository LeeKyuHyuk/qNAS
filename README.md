# QNAS

**Default root password:** `qnas`

### Preparing Build Environment

Ubuntu 18.04.2 LTS is recommended.

#### **Ubuntu 18.04.2 LTS**

```bash
$ sudo apt install make gcc g++
```

### Get QNAS Source code

``` bash
git clone --depth 1 https://github.com/LeeKyuHyuk/qnas.git
```

### Build QNAS

Download the source code by doing `make download`.

``` bash
make download
make all
```

### Build Toolchain

``` bash
make toolchain
```

```
$ x86_64-qnas-linux-gnu-gcc --version
x86_64-qnas-linux-gnu-gcc (QNAS x86_64 2019.12) 9.2.0
Copyright (C) 2019 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

### Build System

``` bash
make system
```

### Build Kernel

``` bash
make kernel
```

### Generate QNAS iso image

``` bash
make image
```

### Built With

- Binutils 2.29.1
- Busybox 1.30.1
- Dosfstools 4.1
- E2fsprogs 1.44.4
- Fakeroot 1.23
- Gcc 8.2.0
- Genimage 10
- Gmp 6.1.2
- libcap 2.26
- libconfuse 3.2.2
- Linux 4.14.74
- Mpc 1.1.0
- Mpfr 4.0.1
- Mtools 4.0.21
- Musl 1.1.21
- Openssh 7.9p1
- Openssl 1.0.2p
- Pkg-conf 0.29.2
- Util-linux 2.33
- Zlib 1.2.11

### Thanks to

- [Linux From Scratch](http://www.linuxfromscratch.org/lfs/view/development/)
- [Cross Linux From Scratch (CLFS)](http://clfs.org/)
- [PiLFS](http://www.intestinate.com/pilfs/)
- [Buildroot](https://buildroot.org/)
