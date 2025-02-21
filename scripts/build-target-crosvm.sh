#!/usr/bin/env -S bash -e

export CROSVM_DIR=$BASE_DIR/crosvm

if [ ! -d "$CROSVM_DIR" ]; then
	>&2 echo "CROSVM_DIR does not exist"
	exit 1
fi

cd "$CROSVM_DIR" || exit 1

git submodule update --init || true

#
# If you don't have the tools, see './tools/install-deps'
#
cargo build --features=gdb

