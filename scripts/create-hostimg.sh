#!/usr/bin/env -S bash -e

SCRIPT_NAME=$(realpath "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_NAME}")

# shellcheck disable=SC1090
. "${SCRIPT_DIR}/${SYSROOT_JAIL:-chroot}-utils.sh"

# Check required env variables
[ ! -d "$BASE_DIR" ] && sysroot_exit_error 1 "BASE_DIR does not exist"
[ -z "$UBUNTU_BASE" ] && sysroot_exit_error 1 "UBUNTU_BASE is not set"
[ -z "$UBUNTU_PKGLIST" ] && sysroot_exit_error 1 "UBUNTU_PKGLIST is not set"

PKGLIST=$(tr '\n' ' ' < "$UBUNTU_PKGLIST")
EXTRA_PKGLIST=
HOSTBUILD=1

USERNAME=$1
GROUPNAME=$2
if [ "x$EFI" = "x1" ]; then
OUTFILE=ubuntuhost-efi.qcow2
else
OUTFILE=ubuntuhost.qcow2
fi
OUTDIR=$BASE_DIR/images/host
SIZE=20G

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
	echo "$0 -o <output directory> -s <image size> -u <ubuntu_base> -p <pkglist>"
}

while getopts "h?u:o:s:p:e:" opt; do
	case "$opt" in
		h|\?)	usage
			exit 0
			;;
		u)	UBUNTU_BASE=$OPTARG
			;;
		p)	PKGLIST=$OPTARG
			;;
		e)	EXTRA_PKGLIST=$OPTARG
			;;
		o)	OUTDIR=$OPTARG
			;;
		s)	SIZE=$OPTARG
			;;
	esac
done

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
Gateway=192.168.7.1
Address=192.168.7.2/24
EOF
	systemctl enable systemd-networkd
	sed 's/#DNS=/DNS=8.8.8.8/' -i /etc/systemd/resolved.conf
	sed 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' -i /etc/ssh/sshd_config
	"

echo "Installing kernel modules"
sudo make -C"$BASE_DIR/linux" INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$TEMP_SYSROOT_DIR" -j"$(nproc)" modules_install

if [ "x$PAM" = "x1" ] && [ -d "${FWOPEN}/coreboot/util/ksmi/ksmi-pam" ]; then
	if [ -d "${BASE_DIR}/linux/drivers/firmware/ksmi" ]; then
		echo "Installing PAM module"
		sudo make -C"$FWOPEN/coreboot/util/ksmi/ksmi-pam" INSTALL_MOD_ROOT="$TEMP_SYSROOT_DIR" -j"$(nproc)" install
	else
		echo "PAM install cancelled. KSMI driver not present"
	fi
fi

sysroot_unmount_all "$TEMP_SYSROOT_DIR"
sync

echo "Create image file"
sysroot_create_image_file "$TEMP_SYSROOT_DIR" "$OUTFILE" "$SIZE"

if [ ! -d "$OUTDIR" ]; then
	echo "Creating output dir.."
	mkdir -p "$OUTDIR"
fi

mv "$OUTFILE" "$OUTDIR"
echo "Output saved at $OUTDIR/$OUTFILE"
sync
