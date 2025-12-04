#!/usr/bin/env -S bash -e

[ -z "$FWOPEN" ] && FWOPEN=$PWD/uefi/firmware-open
[ -z "$TARGET" ] && TARGET=qemu
XGXX=$FWOPEN/coreboot/util/crossgcc/xgcc/bin/x86_64-elf-gcc

if [ "x$1" = "xclean" ]; then
	cd $FWOPEN/coreboot; make distclean; cd -
	cd $FWOPEN/edk2/BaseTools; make clean; cd -
	rm -rf $FWOPEN/coreboot/build/*
	rm -rf $FWOPEN/edk2/Build/*
	rm -rf $FWOPEN/build
	rm -rf build/$TARGET
	rm -rf build/*.rom
	exit 0
fi

if [ "x$1" = "xsetup" ]; then
	pushd $FWOPEN
	git submodule update --init --checkout --recursive
	git lfs pull
	popd
	exit 0
fi

if [ ! -e "$XGXX" ]; then
	cd $FWOPEN/coreboot
	make crossgcc CPUS=$(nproc)
fi

if [ "x$RUSTSETUP" = "x1" ]; then
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	rustup toolchain install stable
	rustup default 1.85.0-x86_64-unknown-linux-gnu
	rustup target add x86_64-unknown-uefi
fi

cd $FWOPEN
if [ ! -e "$FWOPEN/edk2/MdeModulePkg/Universal/BdsDxe/Loadfile.h" ]; then
	cp ../../scripts/coreboot.config models/qemu/coreboot.config
	cp ../../uefi/UefiPayloadPkg/build.sh scripts/build.sh
	cp ../../uefi/UefiPayloadPkg/* edk2/UefiPayloadPkg/
fi

if [ ! -e $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/MOK-PK.der ]; then
	cp $KEYDIR/*.der $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
	cp $KEYDIR/*.esl $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
	cp $KEYDIR/*.auth $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
fi

. ~/.cargo/env
BUILD_TYPE=$BUILD_TYPE ./scripts/build.sh $TARGET
[ -e "${BASE_DIR}/build/firmware.rom" ] && rm ${BASE_DIR}/build/firmware.rom
[ ! -d "${BASE_DIR}/build/${TARGET}" ] && mkdir -p $BASE_DIR/build/$TARGET
cp $FWOPEN/build/$TARGET/firmware.rom $BASE_DIR/build/$TARGET
