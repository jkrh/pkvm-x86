#!/usr/bin/env -S bash -e

QEMU_DIR=$BASE_DIR/qemu
QEMU_BUILD_DIR=$BASE_DIR/qemu/build
QEMU_ROMS_DIR=$BASE_DIR/qemu/roms

if [ ! -d "$QEMU_DIR" ]; then
	>&2 echo "QEMU_DIR does not exist"
	exit 1
fi

OPENGL="${OPENGL:-1}"
SPICE="${SPICE:-1}"
SDL="${SDL:-1}"
VIRGL="${VIRGL:-1}"
DEBUG="${DEBUG:-1}"

if [ -n "$OPENGL" ]; then
	echo "OpenGL enabled"
	OPENGL="--enable-opengl"
else
	echo "OpenGL disabled"
	OPENGL="--disable-opengl"
fi

if [ -n "$SPICE" ]; then
	echo "Spice enabled"
	SPICE="--enable-spice"
else
	echo "Spice disabled"
	SPICE="--disable-spice"
fi

if [ -n "$SDL" ]; then
	echo "SDL enabled"
	SDL="--enable-sdl --audio-drv-list=sdl"
else
	echo "SDL disabled"
	SDL="--disable-sdl --audio-drv-list="
fi

if [ -n "$VIRGL" ]; then
	echo "VIRGL enabled"
	VIRGL="--enable-virglrenderer"
else
	echo "VIRGL disabled"
	VIRGL="--disable-virglrenderer"
fi

if [ -n "$DEBUG" ]; then
	echo "Debug qemu build"
	DEBUG="--enable-debug"
fi

NJOBS=$(nproc)

do_clean()
{
	cd "${QEMU_BUILD_DIR}" || return 1
	make clean
}

do_distclean()
{
	rm -rf "${QEMU_BUILD_DIR}"
}

do_spice()
{
	echo .
}

do_mesa()
{
	echo .
}

do_qemu()
{
	mkdir -p "$QEMU_BUILD_DIR"
	cd "$QEMU_BUILD_DIR" || return 1

	# shellcheck disable=SC2086
	../configure --prefix=/usr --target-list=x86_64-softmmu \
		--enable-kvm \
		--disable-docs \
		$SPICE \
		$OPENGL \
		$SDL \
		$VIRGL \
		$DEBUG

	make "-j$NJOBS"

	cd "$QEMU_ROMS_DIR" || return 1
	make "-j$NJOBS" bios
}

if [[ "$#" -eq 1 ]] && [[ "$1" == "distclean" ]]; then
	do_distclean
	exit 0
elif [[ "$#" -eq 1 ]] && [[ "$1" == "clean" ]]; then
	do_clean
	exit 0
fi

do_spice
do_mesa
do_qemu

echo "All ok!"
