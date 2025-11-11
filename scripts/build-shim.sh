#!/bin/sh -e

PYTHONPATH=$PYTHONPATH:$PWD/uefi/firmware-open/edk2/BaseTools/Source/Python

SHIM_GUID="605dab50-e046-4300-abb6-3dd810dd8b23"
KEYDIR=$PWD/build/keydata
DESTDIR=$PWD/build/shim
[ -z "$FWOPEN" ] && FWOPEN=$PWD/uefi/firmware-open

genkey() {
	openssl req -config $PWD/scripts/openssl.cnf \
		-new -x509 -newkey rsa:2048 \
		-nodes -days 36500 -outform DER \
		-keyout "$KEYDIR/$1.priv" \
		-out "$KEYDIR/$1.der"
	openssl x509 -in "$KEYDIR/$1.der" \
		-inform DER -outform PEM -out "$KEYDIR/$1.pem"
	cert-to-efi-sig-list -g $2 "$KEYDIR/$1.der" "$KEYDIR/$1.esl"
}

if [ ! -e $KEYDIR/MOK-DB.esl ]; then
	GUID=$(uuidgen)
	echo "Generating keys for $GUID.."
	mkdir -p $KEYDIR
	touch $KEYDIR/$GUID

	genkey "MOK-PK" $GUID
	genkey "MOK-KEK" $GUID
	genkey "MOK-DB" $GUID

	# Empty revocation list
	cert-to-efi-sig-list -g $GUID /dev/null $KEYDIR/empty-dbx.esl

	touch empty_file.bin
	$PWD/scripts/create_auth_payload.py

	#
	# To use ^ for signing, first import to shim:
	# mokutil --import MOK-DB.der
	#
	# Then sign:
	# sbsign --key MOK-DB.priv --cert MOK-DB.pem bzImage --output bzImage.signed
	# ..
	# kmodsign sha512 MOK-DB.priv MOK-DB.der module.ko
	#
else
	echo "Using existing keys from $KEYDIR"
fi

cd $PWD/uefi/shim
cp $KEYDIR/*.der $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
cp $KEYDIR/*.esl $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
cp $KEYDIR/*.auth $FWOPEN/edk2/UefiPayloadPkg/SecureBootEnrollDefaultKeys/keys/
make clean
make FALLBACK_VERBOSE=1 DEBUG=1 SHIM_DEBUG=1 VENDOR_CERT_FILE=$KEYDIR/MOK-DB.der DESTDIR=$DESTDIR EFIDIR=BOOT DEFAULT_LOADER='\\EFI\\LINUX\\LINUX.EFI' install install-debuginfo
cp *.debug ../../build/shim/boot/efi/EFI/BOOT
