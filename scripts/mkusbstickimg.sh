#!/bin/bash
set -e

IMG_FILE=$1
IMG_SIZE=$2
UEFI_BOOT_APP=$3
VOLUME_LABEL="12345"

echo "Creating clean ${IMG_SIZE}MB raw disk image..."
# Use dd to ensure the image starts as all zeros, eliminating any old GPT/MBR data
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=${IMG_SIZE}

echo "Creating a standard MBR partition table..."
# Use sfdisk with a heredoc for a precise, non-interactive partitioning.
# This creates a single, bootable FAT32 (type 0x0c) partition.
sfdisk "${IMG_FILE}" << EOF
label: dos
, , 0x0c, *
EOF

echo "Mapping partition to loopback device..."
# losetup -P finds a free loop device and creates partition nodes (e.g., /dev/loop0p1)
LOOP_DEV=$(sudo losetup -f -P --show "${IMG_FILE}")
if [ -z "${LOOP_DEV}" ]; then
  echo "Failed to set up loop device."
  exit 1
fi

echo "Formatting partition ${LOOP_DEV}p1 with high compatibility..."
# Format the partition with the specified label
sudo mkfs.fat -F 32 -n "${VOLUME_LABEL}" "${LOOP_DEV}p1"

if [ -f "${UEFI_BOOT_APP}" ]; then
  mkdir ${BASE_BUILD_DIR}/usb-mnt
  sudo mount ${LOOP_DEV}p1 ${BASE_BUILD_DIR}/usb-mnt
  sudo mkdir -p ${BASE_BUILD_DIR}/usb-mnt/efi/boot
  sudo cp ${UEFI_BOOT_APP} ${BASE_BUILD_DIR}/usb-mnt/efi/boot/BOOTX64.efi
  sudo umount ${BASE_BUILD_DIR}/usb-mnt
  rm -r ${BASE_BUILD_DIR}/usb-mnt
fi

echo "Cleaning up loopback device..."
sudo losetup -d "${LOOP_DEV}"

# While not strictly necessary for consistency, sync is still good practice
# to ensure the image is fully on disk before QEMU reads it.
sync

echo "Done. UEFI-safe image '${IMG_FILE}' is ready."
