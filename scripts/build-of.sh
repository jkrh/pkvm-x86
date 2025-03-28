#!/bin/bash -e

FWOPEN=$PWD/uefi/firmware-open
XGXX=$FWOPEN/coreboot/util/crossgcc/xgcc

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
cp ../../scripts/build.sh scripts/build.sh
cp ../../scripts/UefiPayloadPkg.dsc edk2/UefiPayloadPkg/UefiPayloadPkg.dsc

. ~/.cargo/env
./scripts/build.sh qemu
cp $FWOPEN/build/qemu/firmware.rom ../../build
