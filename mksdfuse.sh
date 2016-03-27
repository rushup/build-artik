#!/bin/bash

set -x

test -e $TARGET_DIR/boot.img || exit 0
test -e $TARGET_DIR/sd_boot.img || exit 0
test -e $TARGET_DIR/params.bin || exit 0
test -e $TARGET_DIR/rootfs.tar.gz || exit 0
test -e $TARGET_DIR/modules.img || exit 0

MICROSD_IMAGE=$1

repartition() {
fdisk $1 << __EOF__
n
p
1

+${BOOT_SIZE}M

n
p
2

+${MODULE_SIZE}M

n
p
3


w
__EOF__
}

if [ "$MICROSD_IMAGE" == "1" ]; then
IMG_NAME=${TARGET_BOARD}_sdcard.img
else
IMG_NAME=${TARGET_BOARD}_sdfuse.img
fi

if [ "$MICROSD_IMAGE" == "1" ]; then
	ROOTFS_SIZE=`gzip -l $TARGET_DIR/rootfs.tar.gz | grep rootfs | awk '{ print $2 }'`
	ROOTFS_GAIN=200
else
	ROOTFS_SIZE=`stat -c%s $TARGET_DIR/rootfs.tar.gz`
	ROOTFS_GAIN=100
fi
ROOTFS_SZ=$((ROOTFS_SIZE >> 20))
TOTAL_SZ=`expr $ROOTFS_SZ + $BOOT_SIZE + $MODULE_SIZE + 2 + $ROOTFS_GAIN`

pushd ${TMP_DIR}
dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ

cp $PREBUILT_DIR/$TARGET_BOARD/bl1.bin $TARGET_DIR/
cp $PREBUILT_DIR/$TARGET_BOARD/tzsw.bin $TARGET_DIR/

dd conv=notrunc if=$TARGET_DIR/sd_boot.img of=$IMG_NAME bs=512

repartition $IMG_NAME

sync;sync;sync

sudo kpartx -a -v ${IMG_NAME}

LOOP_DEV1=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 1'`
LOOP_DEV2=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 3'`

sudo dd conv=notrunc if=$TARGET_DIR/boot.img of=$IMG_NAME bs=1M seek=1 count=$BOOT_SIZE

let SEEK_MODULES=(${BOOT_SIZE} + 1)
sudo dd conv=notrunc if=$TARGET_DIR/modules.img of=$IMG_NAME bs=1M seek=$SEEK_MODULES count=$MODULE_SIZE

sudo mkfs.ext4 -F -b 4096 -L rootfs /dev/mapper/${LOOP_DEV2}
test -d mnt || mkdir mnt

sudo mount /dev/mapper/${LOOP_DEV2} mnt
sync

if [ "$MICROSD_IMAGE" == "1" ]; then
sudo tar xf $TARGET_DIR/rootfs.tar.gz -C mnt
sudo sed -i "s/mmcblk0p/mmcblk1p/g" mnt/etc/fstab
else
sudo cp $TARGET_DIR/bl1.bin mnt
sudo cp $TARGET_DIR/bl2.bin mnt
sudo cp $TARGET_DIR/u-boot.bin mnt
sudo cp $TARGET_DIR/tzsw.bin mnt
sudo cp $TARGET_DIR/params.bin mnt
sudo cp $TARGET_DIR/boot.img mnt
sudo cp $TARGET_DIR/modules.img mnt
sudo cp $TARGET_DIR/rootfs.tar.gz mnt
sudo cp $TARGET_DIR/artik_release mnt
fi

sync;sync

sudo umount mnt
sudo kpartx -d ${IMG_NAME}

mv ${IMG_NAME} $TARGET_DIR

popd

ls -al ${TARGET_DIR}/${IMG_NAME}

echo "Done"
