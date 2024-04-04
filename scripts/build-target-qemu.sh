#!/usr/bin/env bash

SPICE="${SPICE:-1}"
OPENGL="${OPENGL:-1}"
SDL="${SDL:-1}"
VIRGL="${VIRGL:-1}"
DEBUG="${DEBUG:-1}"
SSTATIC=""
QSTATIC=""
SHARED_GLAPI=""

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

unset CC
unset LD
unset CXX
unset AR
unset CPP
unset CROSS_COMPILE
unset CFLAGS
unset LDFLAGS
unset ASFLAGS
unset INCLUDES
unset WARNINGS
unset DEFINES

export UBUNTU_BASE=http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz

export PATH=$TOOLDIR/bin:$TOOLDIR/usr/bin:/bin:/usr/bin:$PATH
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export CHROOTDIR=$BASE_DIR/ubuntu

PKGLIST=$(tr '\n' ' ' < "$BASE_DIR/scripts/package.list.22")

NJOBS=`nproc`
USER=`whoami`

set -e

do_unmount()
{
	if [[ $(findmnt -M "$1") ]]; then
		if ! sudo umount "$1" $2; then
			echo "ERROR: failed to umount $1"
			exit 1
		fi
	fi
}

do_unmount_all()
{
	[ -n "$LEAVE_MOUNTS" ] && echo "leaving bind mounts in place." && exit 0

	echo "Unmount all binding dirs"
	cd $BASE_DIR

	do_unmount $CHROOTDIR/build
	do_unmount $CHROOTDIR/proc
	do_unmount $CHROOTDIR/dev -R
}

do_clean()
{
	sudo -E chroot "$CHROOTDIR" sh -c ". /etc/profile; cd /build/qemu/build; make clean"
}

do_distclean()
{
	do_unmount_all
	sudo rm -rf $BASE_DIR/ubuntu
	sudo rm -rf $BASE_DIR/build
	sudo rm -rf $CHROOTDIR
}

do_mount_all()
{
	sudo mount --rbind /dev "$CHROOTDIR/dev"
	sudo mount --make-rslave "$CHROOTDIR/dev"
	sudo mount -t proc none "$CHROOTDIR/proc"
	sudo mount --bind "$BASE_DIR/build" "$CHROOTDIR/build"
}

create_sysroot()
{
	[ ! -d "$CHROOTDIR/build" ] && mkdir -p "$CHROOTDIR/build"
	[ ! -d "$BASE_DIR/build" ] && mkdir "$BASE_DIR/build"
	[ ! -d "/build" ] && sudo mkdir /build

	wget -c "${UBUNTU_BASE}" -P "${CHROOTDIR}"
	tar xf "${CHROOTDIR}/$(basename $UBUNTU_BASE)" -C "${CHROOTDIR}"
	echo "nameserver 8.8.8.8" > "${CHROOTDIR}/etc/resolv.conf"
	sudo chmod a+rwx "${CHROOTDIR}/tmp"

	do_mount_all

	DEBIAN_FRONTEND=noninteractive sudo -E chroot "$CHROOTDIR" sh -c ". /etc/profile; apt-get update; apt-get -y install $PKGLIST"
}

do_sysroot()
{
	if [ ! -d "$CHROOTDIR" ]; then
		create_sysroot
	else
		do_mount_all
	fi
}

copy_qemu()
{
	[ ! -d "$CHROOTDIR/build/qemu/build" ] && mkdir -p $CHROOTDIR/build/qemu/build
	cd $BASE_DIR/qemu
	tar cf - . | sudo tar xf - -C $CHROOTDIR/build/qemu
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
	sudo -E chroot "$CHROOTDIR" sh -c ". /etc/profile; cd /build/qemu/build; ../configure --prefix=/usr --target-list=x86_64-softmmu --enable-kvm $SPICE $OPENGL $SDL $VIRGL $DEBUG"
	sudo -E chroot "$CHROOTDIR" sh -c ". /etc/profile; cd /build/qemu/build; make -j$NJOBS"
}

if [[ "$#" -eq 1 ]] && [[ "$1" == "distclean" ]]; then
	do_distclean
	exit 0
fi

trap do_unmount_all SIGHUP SIGINT SIGTERM EXIT

do_sysroot

if [[ "$#" -eq 1 ]] && [[ "$1" == "clean" ]]; then
	do_clean
	exit 0
fi

copy_qemu
do_spice
do_mesa
do_qemu

echo "All ok!"
