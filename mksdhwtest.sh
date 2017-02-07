#!/bin/bash

set -x
set -e

HWTEST_RECOVERY_IMAGE=false

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "-o [RESULT_DIR]	Result directory"
	echo "-f [tarball]	Specify -hwtest.tar to do hwtest"
	echo "--recovery	Generate recovery image after hwtest"
	echo "--hwtest-rootfs	Specify rootfs path for hwtest"
	echo "--hwtest-mfg	Specify mfg path for hwtest"

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
			-o)
				RESULT_DIR="$2"
				shift ;;
			-f)
				TEST_IMAGE=`readlink -e "$2"`
				shift ;;
			--recovery)
				HWTEST_RECOVERY_IMAGE=true
				shift ;;
			--hwtest-rootfs)
				HWTEST_ROOTFS=`readlink -e "$2"`
				shift ;;
			--hwtest-mfg)
				HWTEST_MFG=`readlink -e "$2"`
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

if [ "$RESULT_DIR" != "" ]; then
	TARGET_DIR=$(readlink -f "$RESULT_DIR")
fi

SD_BOOT=sd_boot_sdboot.img
if [ "$HWTEST_ROOTFS" == "" ]; then
	HWTEST_ROOTFS=$TARGET_DIR/rootfs.tar.gz
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

if $HWTEST_RECOVERY_IMAGE; then
	HWTEST_SDBOOT=sd_boot_hwtest_recovery.img
	PARAMS_NAME=params_hwtest_recovery.bin
else
	HWTEST_SDBOOT=sd_boot_hwtest.img
	PARAMS_NAME=params_hwtest.bin
fi

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

renew_partition() {
fdisk $1 << __EOF__
p
d
3
n
p
3
${ROOTFS_START_SECTOR}


w
__EOF__
}

gen_hwtest_boot()
{
	cp $SD_BOOT $HWTEST_SDBOOT
	dd conv=notrunc if=$PARAMS_NAME of=$HWTEST_SDBOOT seek=$ENV_OFFSET bs=512
}

gen_image()
{
	if $HWTEST_RECOVERY_IMAGE; then
		IMG_NAME=${TARGET_BOARD}_hwtest-${BUILD_VERSION}-${BUILD_DATE}.img
		ROOTFS_SIZE=`stat -c%s $TARGET_DIR/rootfs.tar.gz`
		ROOTFS_GAIN=400
	else
		IMG_NAME=${TARGET_BOARD}_hwtest.img
		ROOTFS_SIZE=`gzip -l $HWTEST_ROOTFS | grep -v compressed | awk '{ print $2 }'`
		if [ "$HWTEST_MFG" != "" ]; then
			MFG_SIZE=`gzip -l $HWTEST_MFG | grep -v compressed | awk '{ print $2 }'`
			let "ROOTFS_SIZE += MFG_SIZE"
		fi
		ROOTFS_GAIN=200
	fi

	ROOTFS_SZ=$((ROOTFS_SIZE >> 20))
	TOTAL_SZ=`expr $ROOTFS_SZ + $BOOT_SIZE + $MODULE_SIZE + 2 + $ROOTFS_GAIN`

	if [ "$TEST_IMAGE" == "" ]; then
		dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ
		dd conv=notrunc if=$TARGET_DIR/$HWTEST_SDBOOT of=$IMG_NAME bs=512
		sync
		repartition $IMG_NAME
	else
		tar xf $TEST_IMAGE
		if $HWTEST_RECOVERY_IMAGE; then
			dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ
			dd conv=notrunc if=${TARGET_BOARD}_hwtest.img of=$IMG_NAME bs=1M
			dd conv=notrunc if=$PARAMS_NAME of=$IMG_NAME seek=$ENV_OFFSET bs=512
			renew_partition $IMG_NAME
		fi

		sync
	fi

	sync;sync;sync
}

install_output()
{
	sudo kpartx -a -v ${IMG_NAME}
	sync;sync;sync

	LOOP_DEV1=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 1'`
	LOOP_DEV2=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 3'`

	if [ "$TEST_IMAGE" != "" ]; then
		sudo e2fsck -f -y /dev/mapper/${LOOP_DEV2}
		sudo resize2fs /dev/mapper/${LOOP_DEV2}
	fi

	if [ "$TEST_IMAGE" == "" ]; then
		sudo su -c "dd conv=notrunc if=$TARGET_DIR/boot.img of=$IMG_NAME \
			bs=1M seek=$SKIP_BOOT_SIZE count=$BOOT_SIZE"

		sudo su -c "dd conv=notrunc if=$TARGET_DIR/modules.img of=$IMG_NAME \
			bs=1M seek=$MODULE_START_OFFSET count=$MODULE_SIZE"

		sudo su -c "mkfs.ext4 -F -b 4096 -L rootfs /dev/mapper/${LOOP_DEV2}"
	fi

	test -d mnt || mkdir mnt

	sudo su -c "mount /dev/mapper/${LOOP_DEV2} mnt"
	sync

	if [ "$TEST_IMAGE" == "" ]; then
		sudo su -c "tar xf $HWTEST_ROOTFS -C mnt"
		if [ "$HWTEST_MFG" != "" ]; then
			test -d tmp_mfg || mkdir tmp_mfg
			sudo su -c "tar xf $HWTEST_MFG -C tmp_mfg"
			sudo su -c "cp -rf tmp_mfg/* mnt"
			sudo rm -rf tmp_mfg
		fi
	fi

	if $HWTEST_RECOVERY_IMAGE; then
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
	[ -e $TARGET_DIR/artik_release ] && sudo su -c "cp $TARGET_DIR/artik_release mnt/etc"

	sync;sync
	sudo umount mnt
	sudo kpartx -d ${IMG_NAME}

	rm -rf mnt
}

pushd ${TARGET_DIR}

if [ "$TEST_IMAGE" == "" ]; then
	gen_hwtest_boot
fi
gen_image
install_output

popd

ls -al ${TARGET_DIR}/${IMG_NAME}

echo "Done"
