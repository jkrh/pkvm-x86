#!/bin/sh -e

PYTHONPATH=$PYTHONPATH:$FWOPEN/edk2/BaseTools/Source/Python
SHIM_GUID="605dab50-e046-4300-abb6-3dd810dd8b23"
GUID=$(uuidgen)

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

echo "Generating keys for $GUID.."
mkdir -p $KEYDIR
touch $KEYDIR/$GUID

genkey "MOK-PK" $GUID
genkey "MOK-KEK" $GUID
genkey "MOK-DB" $GUID

# Empty revocation list
cert-to-efi-sig-list -g $GUID /dev/null $KEYDIR/empty-dbx.esl

touch $KEYDIR/empty_file.bin
$PWD/scripts/create_auth_payload.py $KEYDIR

#
# If the key import is allowed:
# mokutil --import MOK-DB.der
# ..
# sbsign --key MOK-DB.priv --cert MOK-DB.pem bzImage --output bzImage.signed
# ..
# kmodsign sha512 MOK-DB.priv MOK-DB.der module.ko
#
