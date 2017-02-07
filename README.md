# ARTIK Fedora Root file system
## Contents
1. [Introduction](#1-introduction)
2. [Directory structure](#2-directory-structure)
3. [Build guide](#3-build-guide)
4. [Install guide](#4-install-guide)

## 1. Introduction
This 'build-artik' repository helps to create an ARTIK sd fuse image which can
do eMMC recovery from sdcard. Due to long build time of fedora image, the root
file system is provided by prebuilt binary and download it from server during
build.

---
## 2. Directory structure
+ config: Build configurations for artik5 and artik10
	+ common.cfg: common configurations for artik5 and artik10
	+ artik5.cfg: common.cfg + artik5 specific configurations
	+ artik10.cfg: common.cfg + artik10 specific configurations
	+ artik710.cfg: common.cfg + artik710 specific configurations
	+ artik710s.cfg: common.cfg + artik710 + artik710s specific configurations
	+ artik530.cfg: common.cfg + artik530 specific configurations
+ prebuilt : prebuilt binaries for artik5 and artik10
	+ artik5: early stage bootloaders of artik5
	+ artik10: early stage bootloaders of artik10
+ build_uboot.sh: u-boot build script
+ build_kernel.sh: linux kernel build script
+ build_fedora.sh: fedora build script
+ expand_rootfs.sh: Expand the last rootfs partition of microsd card
+ mkbootimg.sh: generate /boot partition image which contains kernel, dtb and ramdisk
+ mksdboot.sh: generate a sdcard early boot image(from bl1 to u-boot)
+ mksdfuse.sh: build script for generating sd fusing image from binaries
+ release.sh: build u-boot/kernel and generate sd fusing image

---
## 3. Build guide
### 3.1 Install packages
```
sudo apt-get install kpartx u-boot-tools gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu
```

### 3.2 Download BSP sources
#### 1. Download through repo tool
You can download source codes using repo tool. To install the repo tool,
    https://source.android.com/source/downloading.html
* Download source
+ ARTIK710>
```
mkdir artik710
cd artik710
repo init -u https://github.com/SamsungARTIK/manifest.git -m artik710_bsp.xml
repo sync
```

+ ARTIK530>
```
mkdir artik530
cd artik530
repo init -u https://github.com/SamsungARTIK/manifest.git -m artik530_bsp.xml
repo sync
```

#### 2. clone by manual

Please ensure u-boot-artik and linux-artik directory on top of the build-artik.
+ ARTIK710>
<br>
u-boot-artik/
linux-artik/
build-artik/
boot-firmwares-artik710
</br>
```
mkdir artik710
cd artik710
git clone https://github.com/SamsungARTIK/linux-artik.git -b A710_os_2.0.0
git clone https://github.com/SamsungARTIK/u-boot-artik.git -b A710_os_2.0.0
git clone https://github.com/SamsungARTIK/build-artik.git -b A710_os_2.0.0
git clone https://github.com/SamsungARTIK/boot-firmwares-artik710.git -b A710_os_2.0.0
cd build-artik
```
+ ARTIK530>
<br>
u-boot-artik/
linux-artik/
build-artik/
boot-firmwares-artik530
</br>
```
mkdir artik530
cd artik530
git clone https://github.com/SamsungARTIK/linux-artik.git -b A530_os_1.0.0
git clone https://github.com/SamsungARTIK/u-boot-artik.git -b A530_os_1.0.0
git clone https://github.com/SamsungARTIK/build-artik.git -b A530_os_1.0.0
git clone https://github.com/SamsungARTIK/boot-firmwares-artik530.git -b A530_os_1.0.0
cd build-artik
```

### 3.3 Generate a sd fuse image(for eMMC recovery from sd card)
+ artik710
```
./release.sh -c config/artik710.cfg
```

The output will be 'output/images/artik710/YYYYMMDD.HHMMSS/artik710_sdfuse.img'

+ artik530
```
./release.sh -c config/artik530.cfg
```

The output will be 'output/images/artik530/YYYYMMDD.HHMMSS/artik530_sdfuse.img'

### 3.3 Generate a sd bootable image(for SD Card Booting)
+ artik710
```
./release.sh -c config/artik710.cfg -m
```

+ artik530
```
./release.sh -c config/artik530.cfg -m
```

---
### 4. Install guide
Please refer https://developer.artik.io/documentation/updating-artik-image.html

---
### 5. Full build guide
This will require long time to make a fedora rootfs. You'll require to install
fed-artik-tools and set up chroot environment before doing this.
https://github.com/SamsungARTIK/fed-artik-tools

#### 1. Clone whole source tree
+ artik710
```
mkdir artik710_full
cd artik710_full
repo init -u https://github.com/SamsungARTIK/manifest.git -b A710_os_2.0.0 -m artik710.xml
repo sync
```

+ artik530
```
mkdir artik530_full
cd artik530_full
repo init -u https://github.com/SamsungARTIK/manifest.git -b A530_os_1.0.0 -m artik530.xml
repo sync
```

#### 2. Build with --full-build option
+ artik710
```
cd build-artik
./release.sh -c config/artik710.cfg --full-build
```
+ artik530
```
cd build-artik
./release.sh -c config/artik530.cfg --full-build
```
