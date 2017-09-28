#!/bin/bash

set -e

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Aborting."; exit 1; }
}

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"

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
		esac
	done
}

build()
{
	make distclean
	make $KERNEL_DEFCONFIG
	config=$(cat .config)

	if [[ $config == *"CONFIG_KITRA530=y"* ]]; then
		echo "Building for KItra530..."
		make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs EXTRAVERSION="-$BUILD_VERSION"

		cp arch/arm/boot/dts/s5p4418-kitra530.dtb arch/arm/boot/dts/s5p4418-artik530-raptor-rev03.dtb
	elif [[ $config == *"CONFIG_KITRA710C=y"* ]]; then
		echo "Building for KItra710C..."
		make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs EXTRAVERSION="-$BUILD_VERSION"

		cp arch/arm64/boot/dts/nexell/s5p6818-kitra710C.dtb arch/arm64/boot/dts/nexell/s5p6818-artik710-raptor-rev03.dtb
	else
		make $BUILD_DTB EXTRAVERSION="-$BUILD_VERSION"
	fi
	make $KERNEL_IMAGE -j$JOBS EXTRAVERSION="-$BUILD_VERSION"
	make modules EXTRAVERSION="-$BUILD_VERSION" -j$JOBS
}

build_modules()
{
	mkdir -p $TARGET_DIR/modules
	make modules_install INSTALL_MOD_PATH=$TARGET_DIR/modules INSTALL_MOD_STRIP=1
	make_ext4fs -b 4096 -L modules \
		-l ${MODULE_SIZE}M ${TARGET_DIR}/modules.img \
		${TARGET_DIR}/modules/lib/modules/
	rm -rf ${TARGET_DIR}/modules
}

install_output()
{
	cp arch/$ARCH/boot/$KERNEL_IMAGE $TARGET_DIR
	cp $DTB_PREFIX_DIR/$KERNEL_DTB $TARGET_DIR
	cp vmlinux $TARGET_DIR
}

gen_version_info()
{
	KERNEL_VERSION=`make EXTRAVERSION="-$BUILD_VERSION" kernelrelease | grep -v scripts`
	if [ -e $TARGET_DIR/artik_release ]; then
		sed -i "s/_KERNEL=.*/_KERNEL=${KERNEL_VERSION}/" $TARGET_DIR/artik_release
	fi
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`
if [ "$TARGET_BOARD" == "" ]; then
	print_usage
else
	if [ "$KERNEL_DIR" == "" ]; then
		. $SCRIPT_DIR/config/$TARGET_BOARD.cfg
	fi
fi

test -d $TARGET_DIR || mkdir -p $TARGET_DIR

pushd $KERNEL_DIR

package_check ${CROSS_COMPILE}gcc
package_check make_ext4fs

build
build_modules
install_output
gen_version_info

popd
