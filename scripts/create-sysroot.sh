#!/usr/bin/env -S bash -e

SCRIPT_NAME=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_NAME}")

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

# Check required env variables
[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"
[ -z "$BUILD_SYSROOT_DIR" ] && sysroot_exit_error 1 "BUILD_SYSROOT_DIR is not set"
[ -z "$UBUNTU_BASE" ] && sysroot_exit_error 1 "UBUNTU_BASE is not set"
[ -z "$UBUNTU_PKGLIST" ] && sysroot_exit_error 1 "UBUNTU_PKGLIST is not set"

PKGLIST=$(tr '\n' ' ' < "$UBUNTU_PKGLIST")

do_umount_all() {
	sysroot_do_unmount "${BUILD_SYSROOT_DIR}/crosvm" || true

	build_sysroot_unmount_all || true
}

do_distclean()
{
	do_umount_all || true

	sudo rm -rf "$BUILD_SYSROOT_DIR"
	sudo rm -rf "$BASE_DIR/build"
}

if [[ "$#" -eq 1 ]] && [[ "$1" == "distclean" ]]; then
	do_distclean
	exit 0
fi

if [ ! -d "$BUILD_SYSROOT_DIR" ]; then
	sysroot_set_trap "do_umount_all"
	sysroot_create "$BASE_DIR" "$BUILD_SYSROOT_DIR" "$UBUNTU_BASE" "$PKGLIST"

	# RO mount crosvm and install dev deps
	mkdir -p "${BUILD_SYSROOT_DIR}/crosvm"
	sudo mount --bind -o ro "${BASE_DIR}/crosvm" "${BUILD_SYSROOT_DIR}/crosvm"

	# the toolchain installation needs running through some hoops...
	sysroot_run_commands "$BUILD_SYSROOT_DIR" \
		"set -e; \
		ln -sf /crosvm/rust-toolchain rust-toolchain; \
		ln -fs /usr/share/zoneinfo/Europe/Helsinki /etc/localtime;
		/crosvm/tools/setup; \
		rm rust-toolchain;
		echo '. \${CARGO_HOME:-~/.cargo}/env' >> /root/.profile"
fi

echo "All ok!"

