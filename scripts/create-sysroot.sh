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
	mkdir -p "${BUILD_SYSROOT_DIR}/crosvm"
	sysroot_create "$BASE_DIR" "$BUILD_SYSROOT_DIR" "$UBUNTU_BASE" "$PKGLIST"

	# Rust toolchain installation needs running through some hoops...
	sysroot_run_commands "$BUILD_SYSROOT_DIR" \
		"set -e;
		export RUSTUP_HOME=/usr/local/rustup;
		export CARGO_HOME=/usr/local/cargo;
		export PATH=/usr/local/cargo/bin:\$PATH;
		ln -sf /usr/share/zoneinfo/Europe/Helsinki /etc/localtime;
		curl -LO 'https://static.rust-lang.org/rustup/archive/1.25.1/x86_64-unknown-linux-gnu/rustup-init';
		echo '5cc9ffd1026e82e7fb2eec2121ad71f4b0f044e88bca39207b3f6b769aaa799c *rustup-init' | sha256sum -c -;
		chmod +x rustup-init;
		./rustup-init -y --no-modify-path --profile minimal --default-toolchain none;
		chmod -R a+w \$RUSTUP_HOME \$CARGO_HOME;
		rustup --version;
		rustup default stable;
		cargo --version;
		rustc --version;
		rm rustup-init;
		echo \". \${CARGO_HOME}/env\" >> /root/.profile"
fi

echo "All ok!"
