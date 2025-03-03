#!/usr/bin/env -S bash -e

[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"

copy_kernel()
{
	[ ! -d "$BASE_DIR/build/linux" ] && mkdir -p "$BASE_DIR/build/linux"
	rsync -aWt --filter=":- .gitignore" --no-compress "$BASE_DIR/linux" "$BASE_DIR/build/"
}

copy_kernel

cd "$BASE_DIR/build/linux"
make CC="$CC" -j$(nproc) nixos_guest_defconfig bzImage modules
