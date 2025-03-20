#!/usr/bin/env -S bash -e

SCRIPT_NAME=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_NAME}")

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

# Check required env variables
[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"
[ -z "$UBUNTU_BASE" ] && sysroot_exit_error 1 "UBUNTU_BASE is not set"
[ -z "$UBUNTU_PKGLIST" ] && sysroot_exit_error 1 "UBUNTU_PKGLIST is not set"

PKGLIST=$(grep -v "\-dev" < "$UBUNTU_PKGLIST" |tr '\n' ' ' )
EXTRA_PKGLIST=
HOSTBUILD=0

USERNAME=$1
GROUPNAME=$2
if [ "x$EFI" = "x1" ]; then
OUTFILE=ubuntuguest-efi.qcow2
else
OUTFILE=ubuntuguest.qcow2
fi
OUTDIR=$BASE_DIR/images/guest
SIZE=10G

do_cleanup()
{
	echo "${FUNCNAME[0]}: enter"

	sysroot_unmount_all "$TEMP_SYSROOT_DIR"

	if [ -f "$OUTDIR/$OUTFILE" ]; then
		sudo chown "$USERNAME:$GROUPNAME" "$OUTDIR/$OUTFILE"
	fi

	sudo rm -rf "$TEMP_SYSROOT_DIR"
}

usage() {
	echo "$0 -k <guest_kernel> -o <output directory> -s <image size> -u <ubuntu_base> -p <pkglist>"
}

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

[ ! -d "$GUEST_KERNEL" ] && sysroot_exit_error 1 "GUEST_KERNEL directory does not exist"

# Create sysroot dir
TEMP_SYSROOT_DIR=$(mktemp -d --tmpdir="$(pwd)/build")
export TEMP_SYSROOT_DIR
[ ! -d "$TEMP_SYSROOT_DIR" ] && sysroot_exit_error 1 "Tempdir $TEMP_SYSROOT_DIR creation failed"

trap do_cleanup SIGHUP SIGINT SIGTERM EXIT

echo "Creating sysroot"
PACKAGES="$PKGLIST $EXTRA_PKGLIST"
sysroot_create "$BASE_DIR" "$TEMP_SYSROOT_DIR" "$UBUNTU_BASE" "$PACKAGES"

echo "Configuring sysroot"
sysroot_run_commands "$TEMP_SYSROOT_DIR" "
	set -ex
	update-alternatives --set iptables /usr/sbin/iptables-legacy
	adduser --disabled-password --gecos \"\" ubuntu
	passwd -d ubuntu
	usermod -aG sudo ubuntu

	mkdir -p /etc/systemd/network
	cat << EOF >> /etc/systemd/network/99-wildcard.network
[Match]
Name=enp0*

[Network]
DHCP=no
Gateway=192.168.8.1
Address=192.168.8.3/24
EOF
	systemctl enable systemd-networkd
	sed 's/#DNS=/DNS=8.8.8.8/' -i /etc/systemd/resolved.conf
	sed 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' -i /etc/ssh/sshd_config
	"

echo "Installing kernel modules"
sudo make -C"$GUEST_KERNEL" INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$TEMP_SYSROOT_DIR" -j"$(nproc)" modules_install

sysroot_unmount_all "$TEMP_SYSROOT_DIR"
sync

echo "Create image file"
sysroot_create_image_file "$TEMP_SYSROOT_DIR" "$OUTFILE" "$SIZE"

if [ ! -d "$OUTDIR" ]; then
	mkdir -p "$OUTDIR"
fi

cp -f "$BASE_DIR/linux/arch/x86_64/boot/bzImage" "$OUTDIR"
mv "$OUTFILE" "$OUTDIR"
echo "Output saved at $OUTDIR"
