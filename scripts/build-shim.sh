#!/bin/sh -e

KEYDIR=$PWD/build/keydata
DESTDIR=$PWD/build/efi

if [ ! -e $KEYDIR/MOK.der ]; then
	echo "Generating keys.."
	mkdir -p $KEYDIR
	openssl req -config $PWD/scripts/openssl.cnf \
		-new -x509 -newkey rsa:2048 \
		-nodes -days 36500 -outform DER \
		-keyout "$KEYDIR/MOK.priv" \
		-out "$KEYDIR/MOK.der"
	openssl x509 -in "$KEYDIR/MOK.der" \
		-inform DER -outform PEM -out "$KEYDIR/MOK.pem"
	#
	# To use ^ for signing, first import to shim:
	# mokutil --import MOK.der
	#
	# Then sign:
	# sbsign --key MOK.priv --cert MOK.pem bzImage --output bzImage.signed
	# ..
	# kmodsign sha512 MOK.priv MOK.der module.ko
	#
else
	echo "Using existing keys from $KEYDIR"
fi

cd $PWD/uefi/shim
cp $KEYDIR/MOK.der pub.cer
make DESTDIR=$DESTDIR EFIDIR=efi install
