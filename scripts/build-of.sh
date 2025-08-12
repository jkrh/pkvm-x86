#!/bin/bash -e

FWOPEN=$PWD/uefi/firmware-open
XGXX=$FWOPEN/coreboot/util/crossgcc/xgcc

if [ "x$1" = "xclean" ]; then
	cd $FWOPEN/coreboot; make distclean; cd -
	rm -rf $FWOPEN/coreboot/build/*
	rm -rf $FWOPEN/edk2/Build/*
	rm -rf build/*.rom
	exit 0
fi

if [ ! -d "$XGXX" ]; then
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
cp ../../scripts/coreboot.config models/qemu/coreboot.config
cp ../../uefi/UefiPayloadPkg/build.sh scripts/build.sh
cp ../../uefi/UefiPayloadPkg/* edk2/UefiPayloadPkg/

. ~/.cargo/env
./scripts/build.sh qemu
cp $FWOPEN/build/qemu/firmware.rom ../../build
