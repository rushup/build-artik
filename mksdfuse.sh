#!/bin/bash

set -x
set -e

SDBOOT_IMAGE=false

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "-m		Generate sd boot image"

	exit 0
}

parse_options()
{
	for opt in "$@"
	do
		case "$opt" in
			-h|--help)
				print_usage
				shift ;;
			-b)
				TARGET_BOARD="$2"
				shift ;;
			-m)
				SDBOOT_IMAGE=true
				shift ;;
			*)
				shift ;;
		esac
	done
}

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`
if [ "$TARGET_BOARD" == "" ]; then
	print_usage
else
	if [ "$TARGET_DIR" == "" ]; then
		. $SCRIPT_DIR/config/$TARGET_BOARD.cfg
	fi
fi

if $SDBOOT_IMAGE; then
	SD_BOOT=sd_boot_sdboot.img
else
	SD_BOOT=sd_boot.img
fi

test -e $TARGET_DIR/boot.img || exit 0
test -e $TARGET_DIR/$SD_BOOT || exit 0
test -e $TARGET_DIR/params.bin || exit 0
test -e $TARGET_DIR/rootfs.tar.gz || exit 0
test -e $TARGET_DIR/modules.img || exit 0

if [ "$BUILD_DATE" == "" ]
then
	BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
fi

BOOT_START_SECTOR=$((SKIP_BOOT_SIZE << 11))
MODULE_START_OFFSET=$(expr $BOOT_SIZE + $SKIP_BOOT_SIZE)
MODULE_START_SECTOR=$((MODULE_START_OFFSET << 11))
ROOTFS_START_OFFSET=$(expr $MODULE_START_OFFSET + $MODULE_SIZE)
ROOTFS_START_SECTOR=$((ROOTFS_START_OFFSET << 11))

repartition() {
fdisk $1 << __EOF__
n
p
1
$BOOT_START_SECTOR
+${BOOT_SIZE}M

n
p
2
${MODULE_START_SECTOR}
+${MODULE_SIZE}M

n
p
3
${ROOTFS_START_SECTOR}

w
__EOF__
}

gen_image()
{
	if $SDBOOT_IMAGE; then
		IMG_NAME=${TARGET_BOARD}_sdcard-${BUILD_VERSION}-${BUILD_DATE}.img
		ROOTFS_SIZE=`gzip -l $TARGET_DIR/rootfs.tar.gz | grep rootfs | awk '{ print $2 }'`
		ROOTFS_GAIN=800
	else
		IMG_NAME=${TARGET_BOARD}_sdfuse-${BUILD_VERSION}-${BUILD_DATE}.img
		ROOTFS_SIZE=`stat -c%s $TARGET_DIR/rootfs.tar.gz`
		ROOTFS_GAIN=200
	fi

	ROOTFS_SZ=$((ROOTFS_SIZE >> 20))
	TOTAL_SZ=`expr $ROOTFS_SZ + $BOOT_SIZE + $MODULE_SIZE + 2 + $ROOTFS_GAIN`

	dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ
	dd conv=notrunc if=$TARGET_DIR/$SD_BOOT of=$IMG_NAME bs=512
	sync

	repartition $IMG_NAME

	sync;sync;sync
}

install_output()
{
	sudo kpartx -a -v ${IMG_NAME}

	LOOP_DEV1=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 1'`
	LOOP_DEV2=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 3'`

	sudo su -c "dd conv=notrunc if=$TARGET_DIR/boot.img of=$IMG_NAME \
		bs=1M seek=$SKIP_BOOT_SIZE count=$BOOT_SIZE"

	sudo su -c "dd conv=notrunc if=$TARGET_DIR/modules.img of=$IMG_NAME \
		bs=1M seek=$MODULE_START_OFFSET count=$MODULE_SIZE"

	sudo su -c "mkfs.ext4 -F -b 4096 -L rootfs /dev/mapper/${LOOP_DEV2}"

	test -d mnt || mkdir mnt

	sudo su -c "mount /dev/mapper/${LOOP_DEV2} mnt"
	sync

	if $SDBOOT_IMAGE; then
		sudo su -c "tar xf $TARGET_DIR/rootfs.tar.gz -C mnt"
		sudo su -c "sed -i 's/mmcblk0p/mmcblk1p/g' mnt/etc/fstab"
		sudo su -c "cp artik_release mnt/etc/"
	else
		case "$CHIP_NAME" in
		s5p6818)
			sudo su -c "cp $TARGET_DIR/bl1-emmcboot.img mnt"
			sudo su -c "cp $TARGET_DIR/fip-loader-emmc.img mnt"
			sudo su -c "cp $TARGET_DIR/fip-secure.img mnt"
			sudo su -c "cp $TARGET_DIR/fip-nonsecure.img mnt"
			sudo su -c "cp $TARGET_DIR/partmap_emmc.txt mnt"
			;;
		s5p4418)
			sudo su -c "cp $TARGET_DIR/bl1-emmcboot.img mnt"
			sudo su -c "cp $TARGET_DIR/bootloader.img mnt"
			sudo su -c "cp $TARGET_DIR/partmap_emmc.txt mnt"
			;;
		*)
			sudo su -c "cp $TARGET_DIR/bl1.bin mnt"
			sudo su -c "cp $TARGET_DIR/bl2.bin mnt"
			sudo su -c "cp $TARGET_DIR/u-boot.bin mnt"
			sudo su -c "cp $TARGET_DIR/tzsw.bin mnt"
			;;
		esac

		sudo su -c "cp $TARGET_DIR/params.bin mnt"
		sudo su -c "cp $TARGET_DIR/boot.img mnt"
		sudo su -c "cp $TARGET_DIR/modules.img mnt"
		sudo su -c "cp $TARGET_DIR/rootfs.tar.gz mnt"
		[ -e $TARGET_DIR/artik_release ] && sudo su -c "cp $TARGET_DIR/artik_release mnt"
	fi
	sync;sync
	sudo umount mnt
	sudo kpartx -d ${IMG_NAME}

	rm -rf mnt
}

pushd ${TARGET_DIR}

gen_image
install_output

popd

ls -al ${TARGET_DIR}/${IMG_NAME}

echo "Done"
