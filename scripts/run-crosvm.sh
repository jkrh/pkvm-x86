#!/bin/sh -e

export PATH=$PWD:$PATH
export IMAGE=ubuntuguest.qcow2
export KERNEL=bzImage
export RAM=4096
export CORECOUNT=2

[ ! -d /var/empty ] && mkdir /var/empty
[ "x$DEBUG" != "x" ] && DEBUG='--gdb 1234' && KERNEL=vmlinux && CORECOUNT=1

crosvm --log-level=debug run $DEBUG $KERNEL --cpus num-cores=$CORECOUNT		\
	--mem size=$RAM --block path=$IMAGE,root --net tap-name=crosvm_tap	\
	--serial type=stdout,hardware=virtio-console,console,stdin		\
	--core-scheduling false
