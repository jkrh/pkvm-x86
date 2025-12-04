#!/bin/sh -e

DESTDIR=$BASE_DIR/build/shim
cd $PWD/uefi/shim

if [ "x$1" = "xclean" ]; then
	rm -rf $DESTDIR
	make clean
	exit 0
fi

if [ "x$BUILD_TYPE" = "xRELEASE" ]; then
	make VENDOR_CERT_FILE=$KEYDIR/MOK-DB.der DESTDIR=$DESTDIR EFIDIR=BOOT \
	     DEFAULT_LOADER='\\EFI\\LINUX\\LINUX.EFI' install
else
	make FALLBACK_VERBOSE=1 DEBUG=1 SHIM_DEBUG=1 VENDOR_CERT_FILE=$KEYDIR/MOK-DB.der \
	     DESTDIR=$DESTDIR EFIDIR=BOOT DEFAULT_LOADER='\\EFI\\LINUX\\LINUX.EFI' \
	     install install-debuginfo
	     cp *.debug $BASE_DIR/build/shim/boot/efi/EFI/BOOT
fi
