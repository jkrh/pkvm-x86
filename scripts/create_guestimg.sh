#!/usr/bin/env -S bash -e

export PATH=$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin
export XDG_DATA_DIRS=/usr/local/share:/usr/share

cd "$(dirname "$0")"
modprobe nbd max_part=8

UBUNTU_STABLE=http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz
CPUS=`nproc`

USERNAME=$1
GROUPNAME=$2
CURDIR=$PWD
UBUNTU_BASE=$UBUNTU_STABLE
PKGLIST=`cat package.list.22 |grep -v "\-dev"`
OUTFILE=ubuntuguest.qcow2
OUTDIR=$BASE_DIR/images/guest
SIZE=10G

[ ! -e "$GUEST_KERNEL" ] && echo "Please provide a kernel directory" && exit 1

do_unmount()
{
	if [[ $(findmnt -M "$1") ]]; then
		sudo umount $1
		if [ $? -ne 0 ]; then
			echo "ERROR: failed to umount $1"
			exit 1
		fi
	fi
}

do_cleanup()
{
	cd $CURDIR
	do_unmount tmp/proc || true
	do_unmount tmp/dev || true
	do_unmount tmp || true
	qemu-nbd --disconnect /dev/nbd0 || true
	sync || true
	if [ -f $OUTDIR/$OUTFILE ]; then
		chown $USERNAME:$GROUPNAME $OUTDIR/$OUTFILE
	fi

	rmmod nbd
	rm -rf tmp linux `basename $UBUNTU_BASE`
}

usage() {
	echo "$0 -k <guest kernel> -o <output directory> -s <image size> | -u"
}

trap do_cleanup SIGHUP SIGINT SIGTERM EXIT

while getopts "h?u:o:s:k:" opt; do
	case "$opt" in
	h|\?)	usage
		exit 0
		;;
	u)	UBUNTU_BASE=$UBUNTU_UNSTABLE
		;;
	o)	OUTDIR=$OPTARG
		;;
	s)	SIZE=$OPTARG
		;;
	k)	GUEST_KERNEL=$OPTARG
		;;
  esac
done

if [ "x$GUEST_KERNEL" = "x" ]; then
	usage
	exit -1
fi

echo "Creating image.."
qemu-img create -f qcow2 $OUTFILE $SIZE
qemu-nbd --connect=/dev/nbd0 $OUTFILE
parted -a optimal /dev/nbd0 mklabel gpt mkpart primary ext4 0% 100%
sync

echo "Formatting & downloading.."
mkfs.ext4 /dev/nbd0p1
wget -c $UBUNTU_BASE
sync

echo "Extracting ubuntu.."
mkdir -p tmp
mount /dev/nbd0p1 tmp
tar xf `basename $UBUNTU_BASE` -C tmp

echo "Installing packages.."
mount --bind /dev tmp/dev
mount -t proc none tmp/proc
echo "nameserver 8.8.8.8" > tmp/etc/resolv.conf
export DEBIAN_FRONTEND=noninteractive
sudo -E chroot tmp apt-get update
sudo -E chroot tmp apt-get -y install $PKGLIST
sudo -E chroot tmp update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo -E chroot tmp adduser --disabled-password --gecos "" ubuntu
sudo -E chroot tmp passwd -d ubuntu
sudo -E chroot tmp usermod -aG sudo ubuntu

cat >>  tmp/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto enp0s6
iface enp0s6 inet static
address 192.168.8.3
gateway 192.168.8.1
EOF

sed 's/#DNS=/DNS=8.8.8.8/' -i tmp/etc/systemd/resolved.conf
sed 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' -i tmp/etc/ssh/sshd_config

echo "Installing kernel modules.."
cd $GUEST_KERNEL
make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=$BASE_DIR/scripts/tmp -j$CPUS modules_install
cd -

if [ ! -d $OUTDIR ]; then
	mkdir -p $OUTDIR
	chown $USERNAME:$GROUPNAME $OUTDIR
fi

cp -f $BASE_DIR/linux/arch/x86_64/boot/bzImage $OUTDIR
mv $OUTFILE $OUTDIR
echo "Output saved at $OUTDIR"
