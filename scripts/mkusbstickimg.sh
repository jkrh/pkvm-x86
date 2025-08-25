#!/bin/bash
set -e

# Define the output file
IMG_FILE=$1
IMG_SIZE_MB=$2

echo "Creating raw disk image..."
qemu-img create -f raw "${IMG_FILE}" "${IMG_SIZE_MB}M"

echo "Creating MBR partition table and FAT32 partition..."
parted -s "${IMG_FILE}" \
  mklabel msdos \
  mkpart primary fat32 1MiB 100%

echo "Mapping partition to loopback device..."
LOOP_DEV=$(sudo losetup -f -P --show "${IMG_FILE}")
if [ -z "${LOOP_DEV}" ]; then
  echo "Failed to set up loop device."
  exit 1
fi

echo "Formatting partition ${LOOP_DEV}p1..."
# CRITICAL: Format the partition, not the whole device!
sudo mkfs.fat -F 32 -n "12345" "${LOOP_DEV}p1"

echo "Cleaning up loopback device..."
sudo losetup -d "${LOOP_DEV}"

echo "Done. Image '${IMG_FILE}' is ready."

