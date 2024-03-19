#!/bin/bash -e

BASEDIR=$PWD
CONFIG_PAYLOAD_FILE=$BASEDIR/build/linux/arch/x86_64/boot/bzImage
XGXX=$BASEDIR/coreboot/util/crossgcc/xgcc

cd $BASEDIR/coreboot
[ ! -d "$XGXX" ] && make crossgcc-i386 CPUS=$(nproc)

make KBUILD_DEFCONFIG=$BASEDIR/scripts/q35_defconfig defconfig
sed -i "/CONFIG_PAYLOAD_FILE=/c\CONFIG_PAYLOAD_FILE=$CONFIG_PAYLOAD_FILE" .config
make CPUS=$(nproc)
cp build/coreboot.rom $BASEDIR/build
