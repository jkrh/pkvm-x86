#!/usr/bin/env -S bash -e

SCRIPT_NAME=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_NAME}")

exit_error() {
	[ -n "$2" ] && >&2 printf "error: %b\n" "$2"
	exit "$1"
}

# Check required env variables
[ -z "$BASE_DIR" ] && exit_error 1 "BASE_DIR is not set"
[ ! -d "$BASE_DIR" ] && exit_error 1 "BASE_DIR does not exist"
[ -z "$UBUNTU_BASE" ] && exit_error 1 "UBUNTU_BASE not set"

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

PACKAGES="build-essential adduser openssh-server iproute2 iptables vim sshfs \
	gnat gnome-terminal sudo python-is-python3 git clang libcap-dev \
	libclang-dev libfdt-dev libgbm-dev libvirglrenderer-dev libwayland-bin \
	libwayland-dev pkg-config protobuf-compiler wayland-protocols curl mokutil"
BUILD_DEPS="qemu gcc"
PKGLIST="/build/package.list"

pkglist_cleanup() {
	echo "Cleanup"
	sysroot_unmount_all "$TEMP_SYSROOT_DIR"

	sudo rm -rf "$TEMP_SYSROOT_DIR"
}

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

