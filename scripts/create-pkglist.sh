#!/usr/bin/env -S bash -e

SCRIPT_NAME=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_NAME}")

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

PACKAGES="build-essential adduser openssh-server iproute2 iptables vim sshfs gnat gnome-terminal sudo python-is-python3"
BUILD_DEPS="qemu gcc"
PKGLIST="/build/package.list"

pkglist_cleanup() {
	echo "Cleanup"
	sysroot_unmount_all "$TEMP_SYSROOT_DIR"

	sudo rm -rf "$TEMP_SYSROOT_DIR"
}

# Check required env variables
[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"
[ -z "$UBUNTU_BASE" ] && sysroot_exit_error 1 "UBUNTU_BASE not set"

mkdir -p "$(pwd)/build"
TEMP_SYSROOT_DIR=$(mktemp -d --tmpdir="$(pwd)/build")
export TEMP_SYSROOT_DIR

if [ -d "$TEMP_SYSROOT_DIR" ]; then
	sysroot_set_trap pkglist_cleanup
	sysroot_create "$BASE_DIR" "$TEMP_SYSROOT_DIR" "$UBUNTU_BASE" ""

	sysroot_run_commands "$TEMP_SYSROOT_DIR" "sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources; apt-get -y update"

	sysroot_run_commands "$TEMP_SYSROOT_DIR" "apt-get -y install $PACKAGES"
	sysroot_run_commands "$TEMP_SYSROOT_DIR" "apt-get -y build-dep $BUILD_DEPS"

	echo "Writing $PKGLIST"
	sysroot_run_commands "$TEMP_SYSROOT_DIR" "dpkg-query -f '\${binary:Package}\n' -W > $PKGLIST"
fi

