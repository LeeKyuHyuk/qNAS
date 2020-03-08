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
$ aarch64-linux-gnu-gcc --version
aarch64-linux-gnu-gcc (GCC) 9.2.0
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

### Thanks to

- [Linux From Scratch](http://www.linuxfromscratch.org/lfs/view/development/)
- [Cross Linux From Scratch (CLFS)](http://clfs.org/)
- [PiLFS](http://www.intestinate.com/pilfs/)
- [Buildroot](https://buildroot.org/)
