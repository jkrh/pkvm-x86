#!/usr/bin/env -S bash -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"
[ -z "$BUILD_SYSROOT_DIR" ] && sysroot_exit_error 1 "BUILD_SYSROOT_DIR is not set"

usage() {
	cat <<EOF
Usage: $0 SCRIPT

Execute build script in an isolated sysroot.

SCRIPT          Build script for the component.

                The SCRIPT should be accessible in isolated sysroot
                environment, and it should contain the name of the
                component: with the optional file extension removed, the
                component name should be the last token of a hyphen or
                underscore delimited string.

                Examples:
                  foo -> foo
                  foo.sh -> foo
                  build-foo.sh -> foo
                  path-/_to/build_target_foo.sh -> foo

                In addition, there should be a directory
                \$BASE_DIR/<component> containing the source code for the
                component.

Options:
  -h|--help     Show this.
EOF
}

if [ -z "$1" ]; then
	sysroot_exit_error 1 "SCRIPT not supplied\n$(usage)"
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	usage
	exit 0
fi

export SCRIPT=$1
# Remove optional extension
COMPONENT=$(basename "$SCRIPT")
COMPONENT=${COMPONENT%.*}
# Split by hyphen and pick the last token
COMPONENT=${COMPONENT##*-}
# Split by underscore and pick the last token
COMPONENT=${COMPONENT##*_}
export COMPONENT

if [ -z "$COMPONENT" ]; then
	sysroot_exit_error 1 "Parsing COMPONENT from $SCRIPT failed"
fi

# Directories outside chroot
export COMPONENT_DIR=$BASE_DIR/${COMPONENT}
export COMPONENT_BUILD_DIR=$BASE_DIR/build/${COMPONENT}

# Directories inside chroot
export COMPONENT_CHROOT_DIR="${COMPONENT_BUILD_DIR#"${BASE_DIR%/}"}"

copy_sources()
{
	rsync -aWt --filter=":- .gitignore" --no-compress \
		"$COMPONENT_DIR" "$(dirname "$COMPONENT_BUILD_DIR")"
}

copy_sources

sysroot_set_trap build_sysroot_unmount_all
build_sysroot_mount_all

sysroot_run_commands "$BUILD_SYSROOT_DIR" \
	"cd /build/; export BASE_DIR=\$(pwd);  \
	exec \"$SCRIPT\"
	"
