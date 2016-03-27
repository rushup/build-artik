#!/bin/bash

set -x
set -e

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

test -e $TARGET_DIR/zImage || die "not found"
test -e $TARGET_DIR/$KERNEL_DTB || die "not found"
test -e $INITRD || die "not found"

test -e $TARGET_DIR || mkdir -p $TARGET_DIR
test -e $TMP_DIR || mkdir -p $TMP_DIR

cp $INITRD $TARGET_DIR/uInitrd

pushd $TMP_DIR
dd if=/dev/zero of=boot.img bs=1M count=$BOOT_SIZE
sudo mkfs.vfat -n boot boot.img
test -d mnt || mkdir mnt
sudo mount -o loop boot.img mnt

sudo cp $TARGET_DIR/zImage mnt
sudo cp $TARGET_DIR/$KERNEL_DTB mnt
sudo cp $TARGET_DIR/uInitrd mnt

sync; sync;
sudo umount mnt

test -d $TARGET_DIR || mkdir -p $TARGET_DIR
mv boot.img $TARGET_DIR

popd
