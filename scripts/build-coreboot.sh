#!/bin/bash -e

TGT=0
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
		TGT=host
		;;
	g)	CONFIG_PAYLOAD_FILE=$BASEDIR/build/linux/arch/x86_64/boot/bzImage
		TGT=guest
		;;
	esac
done

cd $BASEDIR/coreboot
[ $TGT = 0 ] && usage
[ ! -d "$XGXX" ] && make crossgcc-i386 CPUS=$(nproc)

make KBUILD_DEFCONFIG=$BASEDIR/scripts/q35_defconfig defconfig
sed -i "/CONFIG_PAYLOAD_FILE=/c\CONFIG_PAYLOAD_FILE=$CONFIG_PAYLOAD_FILE" .config
make CPUS=$(nproc)

cp build/coreboot.rom $BASEDIR/build/coreboot-$TGT.rom
cp build/cbfs/fallback/ramstage.debug $BASEDIR/build/$TGT-ramstage.debug
cp build/cbfs/fallback/romstage.debug $BASEDIR/build/$TGT-romstage.debug
cp build/cbfs/fallback/bootblock.debug $BASEDIR/build/$TGT-bootblock.debug
