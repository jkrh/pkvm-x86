#!/bin/bash -e

BUILDTGT=0
BASEDIR=$PWD
XGXX=$BASEDIR/coreboot/util/crossgcc/xgcc

usage() {
	echo "$0 -e | -g"
	exit 0
}

while getopts "h?eg" opt; do
	case "$opt" in
	h|\?)	usage
		;;
	e)	CONFIG_PAYLOAD_FILE=$BASEDIR/linux/arch/x86_64/boot/bzImage
		BUILDTGT=1
		;;
	g)	CONFIG_PAYLOAD_FILE=$BASEDIR/build/linux/arch/x86_64/boot/bzImage
		BUILDTGT=2
		;;
	esac
done

cd $BASEDIR/coreboot
[ $BUILDTGT = 0 ] && usage
[ ! -d "$XGXX" ] && make crossgcc-i386 CPUS=$(nproc)

make KBUILD_DEFCONFIG=$BASEDIR/scripts/q35_defconfig defconfig
sed -i "/CONFIG_PAYLOAD_FILE=/c\CONFIG_PAYLOAD_FILE=$CONFIG_PAYLOAD_FILE" .config
make CPUS=$(nproc)

if [ $BUILDTGT = 1 ]; then
	cp build/coreboot.rom $BASEDIR/build/coreboot-host.rom
else
	cp build/coreboot.rom $BASEDIR/build/coreboot-guest.rom
fi
