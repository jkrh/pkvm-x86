#!/usr/bin/env -S bash -e

cd $QEMUDIR

build()
{
	mkdir -p build
	cd build
	../configure --prefix=$TOOLDIR/usr $DEBUG --target-list=x86_64-softmmu --enable-modules --enable-spice --enable-opengl --enable-virglrenderer --enable-slirp
	make -j$NJOBS
	make install
}

slirp-install()
{
	cd $QEMUDIR/subprojects/slirp
	meson build
	DESTDIR=$TOOLDIR ninja -C build install
}

clean()
{
	cd build
	make clean
}

if [ "x$1" = "xclean" ]; then
	clean
	exit 0
fi
build
pkg-config --libs slirp > /dev/null 2>&1 || slirp-install
