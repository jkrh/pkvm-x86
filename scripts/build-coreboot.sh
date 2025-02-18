#!/usr/bin/env -S bash -e

COREBOOT_DIR=$BASE_DIR/coreboot
COREBOOT_BUILD_DIR=$COREBOOT_DIR/build

if [ ! -d "$COREBOOT_DIR" ]; then
	>&2 echo "COREBOOT_DIR does not exist"
	exit 1
fi

XGXX=util/crossgcc/xgcc

COREBOOT_DEFCONFIG=
COREBOOT_PAYLOAD=

usage() {
	cat <<EOF
Usage: ${0} [OPTS] DEFCONFIG PAYLOAD

Build coreboot.

DEFCONFIG       Coreboot defconfig file.
PAYLOAD         Payload file.

Options:
  -h|--help     Show this.

Variables:
IMAGE_SUFFIX            Optional suffix for the image names.
COREBOOT_LINUX_CMDLINE  Optional override for Linux kernel command line.
EOF
}

parse_arguments()
{
	while [[ $# -gt 0 ]]; do
		key="$1"
		case "$key" in
			-h|--help)
				usage
				exit 0
				;;
			*)
				if [ -z "$COREBOOT_DEFCONFIG" ]; then
					COREBOOT_DEFCONFIG=$key
				elif [ -z "$COREBOOT_PAYLOAD" ]; then
					COREBOOT_PAYLOAD=$key
				else
					>&2 echo "Too many positional arguments"
					exit 1
				fi
				;;
		esac
		shift
	done

	if [ -z "$COREBOOT_DEFCONFIG" ]; then
		>&2 echo "error: DEFCONFIG argument not supplied"
		usage
		exit 1
	elif [ -z "$COREBOOT_PAYLOAD" ]; then
		>&2 echo "error: PAYLOAD argument not supplied"
		usage
		exit 1
	fi
}

parse_arguments "$@"

if [ ! -r "${COREBOOT_DEFCONFIG}" ]; then
	>&2 echo "error: Cannot read defconfig $COREBOOT_DEFCONFIG"
	exit 1
elif [ ! -r "${COREBOOT_PAYLOAD}" ]; then
	>&2 echo "error: Cannot read payload $COREBOOT_PAYLOAD"
	exit 1
fi

BUILD_DEFCONFIG="$COREBOOT_DIR/$(basename "$COREBOOT_DEFCONFIG")"
BUILD_PAYLOAD="$COREBOOT_DIR/$(basename "$COREBOOT_PAYLOAD")"

cp "$COREBOOT_DEFCONFIG" "$BUILD_DEFCONFIG"
cp "$COREBOOT_PAYLOAD" "$BUILD_PAYLOAD"

cd "$COREBOOT_DIR"

if [ ! -d $XGXX ]; then
	make crossgcc-i386 CPUS=$(nproc)
fi

rm -rf .config

make KBUILD_DEFCONFIG="$BUILD_DEFCONFIG" defconfig

sed -i "/CONFIG_PAYLOAD_FILE=/c\CONFIG_PAYLOAD_FILE=\"$BUILD_PAYLOAD\"" .config
[ -n "$COREBOOT_LINUX_CMDLINE" ] && \
	sed -i "/CONFIG_LINUX_COMMAND_LINE=/c\CONFIG_LINUX_COMMAND_LINE=\"$COREBOOT_LINUX_CMDLINE\"" .config

make CPUS="$(nproc)"

# Copy artifacts to build directory
suffix=${IMAGE_SUFFIX:+-${IMAGE_SUFFIX}}

cp "$COREBOOT_BUILD_DIR/coreboot.rom" "$BASE_BUILD_DIR/coreboot${suffix}.rom"
cp "$COREBOOT_BUILD_DIR/cbfs/fallback/ramstage.debug" "$BASE_BUILD_DIR/coreboot-ramstage${suffix}.debug"
cp "$COREBOOT_BUILD_DIR/cbfs/fallback/romstage.debug" "$BASE_BUILD_DIR/coreboot-romstage${suffix}.debug"
cp "$COREBOOT_BUILD_DIR/cbfs/fallback/bootblock.debug" "$BASE_BUILD_DIR/coreboot-bootblock${suffix}.debug"
