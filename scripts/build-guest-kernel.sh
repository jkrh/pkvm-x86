#!/usr/bin/env -S bash -e

NJOBS=`nproc`
BASEDIR=$PWD

copy_kernel()
{
	[ ! -d "$BASEDIR/build/linux" ] && mkdir -p "$BASEDIR/build/linux"
	rsync -aWt --filter=":- .gitignore" --no-compress "$BASEDIR/linux" "$BASEDIR/build/"
}

copy_kernel

cd $BASEDIR/build/linux
make CC=$CC -j$NJOBS nixos_guest_defconfig bzImage modules
