#!/bin/bash

#code signer v2.4
CODE_SIGNER="$PREBUILT_DIR/codesigner_v24"

#OEM Private Key
OEM_PRIV_KEY_NAME="$PREBUILT_DIR/sign_keys/a520_b2b_V24.prv"
OEM_PUB_KEY_NAME="$PREBUILT_DIR/sign_keys/a520_b2b_V24.spk"

#u-boot infomation
UBOOT_NAME=u-boot.bin
UBOOT_PADD_NAME=u-boot-dtb_padd.bin
UBOOT_TARGET_BIN=sboot-dtb.bin

#bl2 information
BL2_NAME=espresso3250-spl.bin
BL2_TARGET_BIN=sespresso3250-spl.bin

OUTPUT_DIR=$1

U_BOOT_SIZE_KB=1024
SIG_SIZE_B=256

U_BOOT_SIZE_B=`expr $U_BOOT_SIZE_KB \* 1024`
U_BOOT_PADD_B=`expr $U_BOOT_SIZE_B \- 256`

pushd $OUTPUT_DIR

#Add Zero Padding
#---------------------------------------------
#u-boot: Add padding(0x00) to u-boot image.
cp $UBOOT_NAME $UBOOT_PADD_NAME
truncate -s $U_BOOT_PADD_B $UBOOT_PADD_NAME
#--------------------------------------------

#Add Signature
#------------------------------------------------------------------------------------------------------------
#u-boot: Add signature(256B) to the end of input binary.
$CODE_SIGNER -STAGE2 -IMGMAKE -infile=$UBOOT_PADD_NAME -outfile=$UBOOT_TARGET_BIN -pri=$OEM_PRIV_KEY_NAME

#bl2: Add signature(256B) to the end of input binary.
$CODE_SIGNER -STAGE2 -IMGMAKE -infile=$BL2_NAME -outfile=$BL2_TARGET_BIN -pri=$OEM_PRIV_KEY_NAME
#------------------------------------------------------------------------------------------------------------


#Verifying signature
#-----------------------------------------------------------------------------------
#u-boot: Verify added signature with OEM public key.
$CODE_SIGNER -STAGE2 -VERIFY -infile=$UBOOT_TARGET_BIN -pub=$OEM_PUB_KEY_NAME

if [ $? -ne 0 ]; then
	if [ -f "$UBOOT_PADD_NAME" ]; then
		rm -rf $UBOOT_PADD_NAME
	fi
	if [ -f "$UBOOT_TARGET_BIN" ]; then
		rm -rf $UBOOT_TARGET_BIN
	fi
	echo "### u-boot verification: Failed ###"
else
	echo "### u-boot verification: Success ###"
	cp $UBOOT_TARGET_BIN $UBOOT_NAME
	if [ -f "$UBOOT_PADD_NAME" ]; then
		rm -rf $UBOOT_PADD_NAME
	fi
	if [ -f "$UBOOT_TARGET_BIN" ]; then
		rm -rf $UBOOT_TARGET_BIN
	fi

fi

#bl2: Verify added signature with OEM public key.
$CODE_SIGNER -STAGE2 -VERIFY -infile=$BL2_TARGET_BIN -pub=$OEM_PUB_KEY_NAME

if [ $? -ne 0 ]; then
	if [ -f "$BL2_TARGET_BIN" ]; then
		rm -rf $BL2_TARGET_BIN
	fi
	echo "### bl2 verification: Failed ###"
else
	echo "### bl2 verification: Success ###"
	cp $BL2_TARGET_BIN $BL2_NAME
	if [ -f "$BL2_TARGET_BIN" ]; then
		rm -rf $BL2_TARGET_BIN
	fi

fi
#-----------------------------------------------------------------------------------

popd
