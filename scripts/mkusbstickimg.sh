#!/bin/bash
set -e

IMG_FILE=$1
IMG_SIZE=$2
UEFI_BOOT_APP=$3
KSMI_TEST_APP=$4
VOLUME_LABEL="12345"
MARKER_FILE="KS.BAK"

[ -z "$PRIVATEKEY" ] && PRIVATEKEY="$BASE_BUILD_DIR/keydata/MOK-DB.priv"
[ -z "$PUBLICKEY" ] && PUBLICKEY="$BASE_BUILD_DIR/keydata/MOK-DB.pem"

echo "Creating clean ${IMG_SIZE_MB}MB raw disk image..."
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=${IMG_SIZE}

echo "Creating a standard MBR partition table..."
# This creates a single, bootable FAT32 partition starting at sector 2048 (1 MiB).
sfdisk "${IMG_FILE}" << EOF
label: dos
, , 0x0c, *
EOF

# Calculate the partition offset in bytes (2048 sectors * 512 bytes/sector)
OFFSET=$((2048 * 512))

echo "Formatting partition using mformat for maximum compatibility..."
mformat -i "${IMG_FILE}@@${OFFSET}" -F -v "${VOLUME_LABEL}"

echo "Creating marker file..."
MOUNT_POINT=$(mktemp -d)
# Mount the first partition of the image file
sudo mount -o loop,offset=$((2048 * 512)) "${IMG_FILE}" "${MOUNT_POINT}"

# Create the empty marker file
sudo touch "${MOUNT_POINT}/${MARKER_FILE}"
# Add uefi boot app if requested
if [ -n "${UEFI_BOOT_APP}" ] && [ -f "${UEFI_BOOT_APP}" ]; then
  echo "Adding ${UEFI_BOOT_APP} to USB media"
  sudo mkdir -p ${MOUNT_POINT}/efi/boot
	sbsign  --key $PRIVATEKEY \
		--cert $PUBLICKEY ${UEFI_BOOT_APP} \
		--output $BASE_BUILD_DIR/BOOTX64.app.efi.signed
  sudo cp $BASE_BUILD_DIR/BOOTX64.app.efi.signed ${MOUNT_POINT}/efi/boot/BOOTX64.efi
fi
# SMI test application
if [ -n "${KSMI_TEST_APP}" ] && [ -f "${KSMI_TEST_APP}" ]; then
  echo "Adding ${KSMI_TEST_APP} to USB media"
  sudo mkdir -p ${MOUNT_POINT}/efi/boot
	sbsign  --key $PRIVATEKEY \
		--cert $PUBLICKEY ${KSMI_TEST_APP} \
		--output $BASE_BUILD_DIR/KSMItApp.efi.signed
  sudo cp $BASE_BUILD_DIR/KSMItApp.efi.signed ${MOUNT_POINT}/efi/boot/KSMItApp.efi
fi

# Unmount and clean up
sudo sync
sudo umount -l "${MOUNT_POINT}"

while grep -qs "$MOUNT_POINT" /proc/mounts; do
  printf "."
  sleep 1
done

rmdir "${MOUNT_POINT}"

echo "Done, compatible image '${IMG_FILE}' is ready."
