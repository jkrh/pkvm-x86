#!/bin/bash -e

NJOBS=`nproc`
BASEDIR=$PWD

copy_kernel()
{
        [ ! -d "$BASEDIR/build/linux" ] && mkdir -p $BASEDIR/build/linux
        cd $BASE_DIR/linux
        tar cf - . | tar xf - -C $BASE_DIR/build/linux
}

[ ! -d "$BASEDIR/build/linux/arch" ] && copy_kernel

cd $BASEDIR/build/linux
make -j$NJOBS nixos_guest_defconfig bzImage modules
