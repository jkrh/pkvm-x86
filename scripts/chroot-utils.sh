#!/usr/bin/env bash

[ -z "$KERNEL_GENERATION" ] && export KERNEL_GENERATION=1
[ -z "$CONTACT_EMAIL" ] && export CONTACT_EMAIL=email@example.com
if [ -z "$KERNEL_VERSION" ] ; then
	KERNEL_MAJOR=`cat $KERNEL_DIR/include/generated/uapi/linux/version.h |grep LINUX_VERSION_MAJOR | cut -d " " -f 3`
	KERNEL_PATCH=`cat $KERNEL_DIR/include/generated/uapi/linux/version.h |grep LINUX_VERSION_PATCHLEVEL | cut -d " " -f 3`
	KERNEL_SUB=`cat $KERNEL_DIR/include/generated/uapi/linux/version.h |grep LINUX_VERSION_SUBLEVEL | cut -d " " -f 3`
	KERNEL_VERSION="$KERNEL_MAJOR.$KERNEL_PATCH.$KERNEL_SUB"
fi
if [ -z "$KERNEL_CMDLINE" ]; then
	if [ "x$EFI" = "x1" ]; then
		KERNEL_CMDLINE=`cat $BASE_DIR/platform/q35/vars.mk | sed "s/nvme0n1p1/nvme0n1p2/"`
	else
		KERNEL_CMDLINE=`cat $BASE_DIR/platform/q35/vars.mk`
	fi
fi
[ -z "$PRIVATEKEY" ] && PRIVATEKEY="$PWD/build/keydata/MOK-DB.priv"
[ -z "$PUBLICKEY" ] && PUBLICKEY="$PWD/build/keydata/MOK-DB.pem"

# usage: sysroot_error MESSAGE
sysroot_error() {
	>&2 printf "error: %b" "$1"
}

# usage: sysroot_exit_error RC MESSAGE
sysroot_exit_error() {
	[ -n "$2" ] && sysroot_error "$2"
	exit "$1"
}

# usage: sysroot_mount_all SOURCE_DIR SYSROOT_DIR
sysroot_mount_all() {
	[ ! -d "$1" ] && return 1
	[ ! -d "$2" ] && return 1

	sudo mount --rbind /dev "$2/dev"
	sudo mount --make-rslave "$2/dev"
	sudo mount -t proc none "$2/proc"
	sudo mount --bind "$1/build" "$2/build"
	sudo mount --bind -o ro "$1/scripts" "$2/build/scripts"
}

# usage: sysroot_do_unmount MOUNTPOINT [OPTIONS]
sysroot_do_unmount() {
	[ ! -d "$1" ] && return 1

	if [[ $(findmnt -M "$1") ]]; then
		# shellcheck disable=SC2086
		if ! sudo umount "$1" $2; then
			sysroot_error "failed to umount $1"
			return 1
		fi
	fi
}

# usage: sysroot_unmount_all SYSROOT_DIR
sysroot_unmount_all() {
	[ ! -d "$1" ] && return 1

	if [ -n "$LEAVE_MOUNTS" ]; then
		echo "Leaving bind mounts in place"
		return 0
	fi

	echo "Unmount all binding dirs"

	sysroot_do_unmount "$1/build/scripts" -l || true
	sysroot_do_unmount "$1/build" -l || true
	sysroot_do_unmount "$1/proc" -l || true
	sysroot_do_unmount "$1/dev" -R || true
}

# usage: sysroot_run CMD ARGS
# variables:
#   - SYSROOT_EXTRA_VARS for passing env variables as string.
#     Example: export SYSROOT_EXTRA_VARS="FOO=BAR BAZ='QUX QUUX'"
#   - SYSROOT_EXTRA_VARS_ARR for passing env variables as array (when sourced)
#     Example: declare -ag SYSROOT_EXTRA_VARS_ARR=("CORGE=GRAULT GARPLY")
sysroot_run() {
	local sysroot_dir=$1
	shift 1

	if [ ! -d "$sysroot_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SYSROOT_DIR argument does not exist"
		return 1
	elif [ -z "$*" ]; then
		sysroot_error "${FUNCNAME[0]}: ARGS argument is empty"
		return 1
	fi

	# Process extra env variables
	[[ -v SYSROOT_EXTRA_VARS_ARR ]] || declare -ag SYSROOT_EXTRA_VARS_ARR
	while IFS=$'\n' read -r line; do
		[ -n "$line" ] && SYSROOT_EXTRA_VARS_ARR+=("$line")
	done <<< "$(echo "$SYSROOT_EXTRA_VARS" |xargs printf '%s\n')"

	# shellcheck disable=SC2046
	sudo -E chroot "${sysroot_dir}" /usr/bin/env -i \
		$(xargs -d'\n' < "${sysroot_dir}/etc/environment") \
		$(locale |xargs -d'\n') \
		`# :+ is a workaround for empty array` \
		${SYSROOT_EXTRA_VARS_ARR[@]:+"${SYSROOT_EXTRA_VARS_ARR[@]}"} \
		DEBIAN_FRONTEND=noninteractive \
		HOME=/root \
		"$@"
}

# usage: sysroot_run_commands SYSROOT_DIR COMMAND_STRING
# SYSROOT_DIR directory must exist
sysroot_run_commands() {
	local sysroot_dir=$1
	local command_string=$2

	if [ ! -d "$sysroot_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SYSROOT_DIR argument does not exist"
		return 1
	elif [ -z "$command_string" ]; then
		sysroot_error "${FUNCNAME[0]}: COMMAND_STRING argument is empty"
		return 1
	fi

	sysroot_run "$sysroot_dir" bash --login -c "$command_string"
}

# usage: sysroot_run_interactive SYSROOT_DIR
# SYSROOT_DIR directory must exist
sysroot_run_interactive() {
	local sysroot_dir=$1

	if [ ! -d "$sysroot_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SYSROOT_DIR argument does not exist"
		return 1
	fi

	sysroot_run "$sysroot_dir" bash --login -i
}

# usage: sysroot_create SOURCE_DIR SYSROOT_DIR TARBALL_URL PKGLIST
# SOURCE_DIR directory must exist
sysroot_create() {
	local source_dir=$1
	local sysroot_dir=$2
	local tarball_url=$3
	local pkglist=$4

	if [ ! -d "$source_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SOURCE_DIR argument does not exist"
		return 1
	elif [ -z "$sysroot_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SYSROOT_DIR argument is empty"
		return 1
	elif [ -z "$tarball_url" ]; then
		sysroot_error "${FUNCNAME[0]}: TARBALL_URL argument is empty"
		return 1
	elif [ -v "$pkglist" ]; then
		sysroot_error "${FUNCNAME[0]}: PKGLIST argument is not set"
		return 1
	fi

	mkdir -p \
		"$source_dir/build/scripts" \
		"$sysroot_dir/build" \
		"$sysroot_dir/dev"

	wget -c "${tarball_url}" -P "${sysroot_dir}"
	sudo tar xpf "${sysroot_dir}/$(basename "$tarball_url")" -C "${sysroot_dir}"

	rm "${sysroot_dir}/$(basename "$tarball_url")"
	chmod 755 "$sysroot_dir"
	sudo chown root:root "$sysroot_dir"

	echo "nameserver 8.8.8.8" | sudo tee "${sysroot_dir}/etc/resolv.conf" > /dev/null
	sudo chmod a+rwx "${sysroot_dir}/tmp"

	sysroot_mount_all "$source_dir" "$sysroot_dir"

	sysroot_run_commands \
		"$sysroot_dir" \
		"apt-get update; apt-get -y install $pkglist"
}

#
# We do this with mformat in overly complicated fashion for the reason that mkfs.fat
# leaves the TotalSectors32 empty. Edk2 fat driver needs it.
#
mformat_partition() {
	DEVICE="$1"
	PARTITION_NUM="$2"
	PARTITION_PATH="${DEVICE}p${PARTITION_NUM}"
	VOLUME_LABEL="EFIBOOT"
	TEMP_IMAGE="temp_esp.img"

	PARTITION_SECTORS=$(parted -s ${DEVICE} unit s print | sed -e 's/s//g' | grep "^ ${PARTITION_NUM} " | awk '{print $4}')
	SECTOR_SIZE=512 # Assume 512-byte sectors
	PARTITION_BYTES=$((PARTITION_SECTORS * SECTOR_SIZE))

	echo "Partition Size: ${PARTITION_SECTORS} sectors (${PARTITION_BYTES} bytes)"

	truncate -s ${PARTITION_BYTES} ${TEMP_IMAGE}
	mformat -i ${TEMP_IMAGE} -F -v "${VOLUME_LABEL}" ::
	dd if=${TEMP_IMAGE} of=${PARTITION_PATH} bs=4M status=progress
	rm ${TEMP_IMAGE}
}

#
# This is tricky. The large vma gap doesn't actually matter, we are
# running on bare metal and it's just the relocation destination. We
# put it far out so that it doesn't clash with the kernel. We do this
# via vma as otherwise we will corrupt the pe/coff headers.
#
add_kernel_sbat() {
	BZIMAGE="$1"
	OUTPUT_IMAGE="$2"
	SBAT_CSV="$3"

	objcopy --add-section .sbat=${SBAT_CSV} \
		--set-section-flags .sbat=contents,alloc,load,readonly \
		--adjust-section-vma .sbat=0x3000000 \
		--set-section-alignment .sbat=4096 \
		${BZIMAGE} \
		${OUTPUT_IMAGE}
}

# usage: sysroot_create_image_file SYSROOT_DIR FILE SIZE
sysroot_create_image_file() {
	local tmp_image_dir

	local sysroot_dir=$1
	local file=$2
	local size=$3

	if [ ! -d "$sysroot_dir" ]; then
		sysroot_error "${FUNCNAME[0]}: SYSROOT_DIR does not exist"
		return 1
	elif [ -z "$file" ]; then
		sysroot_error "${FUNCNAME[0]}: FILE argument is empty"
		return 1
	elif [ -z "$size" ]; then
		sysroot_error "${FUNCNAME[0]}: SIZE argument is empty"
		return 1
	fi

	tmp_image_dir=$(mktemp -d --tmpdir="$(pwd)/build")
	[ ! -d "$tmp_image_dir" ] && sysroot_exit_error 1 "tempdir $tmp_image_dir creation failed"

	sudo -E bash -ec "
	$(declare -f sysroot_do_unmount)
	$(declare -f mformat_partition)
	$(declare -f add_kernel_sbat)
	create_image_cleanup() {
		set -e
		sysroot_do_unmount '$tmp_image_dir/boot' || true
		sysroot_do_unmount '$tmp_image_dir' -l || true
		sync || true
		qemu-nbd --disconnect /dev/nbd0 || true
		sync || true
		rmmod nbd || true
		rm -rf '$tmp_image_dir'
	}
	trap create_image_cleanup SIGHUP SIGINT SIGTERM EXIT

	set -e
	rmmod nbd || true
	modprobe nbd max_part=8
	rm -rf '$file'
	qemu-img create -f qcow2 '$file' '$size'
	qemu-nbd --connect=/dev/nbd0 '$file'
	sync
	sleep 2

	if [ "x$EFI" = "x1" ]; then
		parted -s /dev/nbd0 mklabel gpt \
			mkpart ESP fat32 1MiB 2GiB \
			set 1 esp on \
			mkpart ROOT ext4 2GiB 100%
		sync
		sleep 2
		mformat_partition /dev/nbd0 1
		if [ -n "$BLOCK_SIZE" ]; then
			mkfs.ext4 -b "$BLOCK_SIZE" /dev/nbd0p2
		else
			mkfs.ext4 /dev/nbd0p2
		fi
		sync
		mount /dev/nbd0p2 '$tmp_image_dir'
		sleep 2
	else
		parted -a optimal /dev/nbd0 mklabel gpt mkpart primary ext4 0% 100%
		sync
		sleep 2
		mkfs.ext4 /dev/nbd0p1
		mount /dev/nbd0p1 '$tmp_image_dir'
		sync
	fi

	rsync -aWPHq --numeric-ids --no-compress '${sysroot_dir}/' '$tmp_image_dir'
	sync

	if [ "x$EFI" != "x1" ]; then
		exit 0
	fi

	mount -o uid=$(id -u),gid=$(id -g) /dev/nbd0p1 '$tmp_image_dir/boot'
	cp -rf $PWD/build/shim/boot/efi/EFI $tmp_image_dir/boot

	echo 'shimx64.efi,BOOT,,This is the boot entry for BOOT' > \
		$tmp_image_dir/boot/EFI/BOOT/BOOTX64.CSV.tmp
	echo 'mmx64.efi,1,Shim Project,shim,1,shim-devel@shim.org' >> \
		$tmp_image_dir/boot/EFI/BOOT/BOOTX64.CSV.tmp
	iconv -f UTF-8 -t UTF-16LE $tmp_image_dir/boot/EFI/BOOT/BOOTX64.CSV.tmp > \
		$tmp_image_dir/boot/EFI/BOOT/BOOTX64.CSV
	rm -f $tmp_image_dir/boot/EFI/BOOT/BOOTX64.CSV.tmp

	mkdir -p $tmp_image_dir/boot/EFI/LINUX
	echo 'LINUX.EFI,$KERNEL_GENERATION,$KERNEL_CMDLINE,kernel,$KERNEL_VERSION,$CONTACT_EMAIL' > \
		$tmp_image_dir/boot/EFI/LINUX/LINUX.CSV.tmp
	iconv -f UTF-8 -t UTF-16LE $tmp_image_dir/boot/EFI/LINUX/LINUX.CSV.tmp > \
		$tmp_image_dir/boot/EFI/LINUX/BOOTX64.CSV
	rm -f $tmp_image_dir/boot/EFI/LINUX/LINUX.CSV.tmp

	if [ "$HOSTBUILD" = "1" ]; then
		add_kernel_sbat $PWD/linux/arch/x86_64/boot/bzImage \
			$PWD/linux/arch/x86_64/boot/bzImage.efi \
			$PWD/scripts/kernel_sbat.csv
		sbsign 	--key $PRIVATEKEY \
			--cert $PUBLICKEY $PWD/linux/arch/x86_64/boot/bzImage.efi \
			--output $tmp_image_dir/boot/EFI/LINUX/LINUX.EFI
	else
		add_kernel_sbat $PWD/build/linux/arch/x86_64/boot/bzImage \
			$PWD/build/linux/arch/x86_64/boot/bzImage.efi \
			$PWD/scripts/kernel_sbat.csv
		sbsign	--key $PRIVATEKEY \
			--cert $PUBLICKEY $PWD/build/linux/arch/x86_64/boot/bzImage.efi \
			--output $tmp_image_dir/boot/EFI/LINUX/LINUX.EFI
	fi

	sbsign  --key $PRIVATEKEY \
		--cert $PUBLICKEY $tmp_image_dir/boot/EFI/BOOT/shimx64.efi \
		--output $tmp_image_dir/boot/EFI/BOOT/shimx64.efi.tmp
	mv $tmp_image_dir/boot/EFI/BOOT/shimx64.efi.tmp $tmp_image_dir/boot/EFI/BOOT/shimx64.efi
	cp $tmp_image_dir/boot/EFI/BOOT/shimx64.efi $tmp_image_dir/boot/EFI/BOOT/BOOTX64.EFI

	sbsign  --key $PRIVATEKEY \
		--cert $PUBLICKEY $tmp_image_dir/boot/EFI/BOOT/mmx64.efi \
		--output $tmp_image_dir/boot/EFI/BOOT/mmx64.efi.tmp
	mv $tmp_image_dir/boot/EFI/BOOT/mmx64.efi.tmp $tmp_image_dir/boot/EFI/BOOT/mmx64.efi

	if [ -e $PWD/build/keydata/MOK-DB.der ]; then
		cp $PWD/build/keydata/MOK-DB.der $tmp_image_dir/boot/EFI/BOOT/
		mkdir -p '$tmp_image_dir/var/lib/shim-signed/mok'
		cp $PWD/build/keydata/MOK-DB.der '$tmp_image_dir/var/lib/shim-signed/mok'
	fi
	"
}

# usage: sysroot_set_trap FUNC
sysroot_set_trap() {
	declare -F "$1" &>/dev/null || return 1

	# shellcheck disable=SC2064
	trap "$1" SIGHUP SIGINT SIGTERM EXIT
}

# usage: build_sysroot_mount_all
# BASE_DIR and BUILD_SYSROOT_DIR must be defined and must exist
build_sysroot_mount_all() {
	if [ ! -d "$BASE_DIR" ]; then
		sysroot_error "${FUNCNAME[0]}: BASE_DIR does not exist"
		return 1
	fi

	if [ ! -d "$BUILD_SYSROOT_DIR" ]; then
		sysroot_error "${FUNCNAME[0]}: BUILD_SYSROOT_DIR does not exist"
		return 1
	fi

	sysroot_mount_all "$BASE_DIR" "$BUILD_SYSROOT_DIR"
}

# usage: build_sysroot_unmount_all
# BASE_DIR and BUILD_SYSROOT_DIR must be defined and must exist
build_sysroot_unmount_all() {
	cd "$BASE_DIR" || return 1

	if [ ! -d "$BUILD_SYSROOT_DIR" ]; then
		sysroot_error "${FUNCNAME[0]}: BUILD_SYSROOT_DIR does not exist"
		return 1
	fi

	sysroot_unmount_all "$BUILD_SYSROOT_DIR"
}

# usage: build_sysroot_run_commands COMMAND_STRING
# BUILD_SYSROOT_DIR must be defined and must exist
build_sysroot_run_commands() {
	local command_string=$1

	if [ ! -d "$BUILD_SYSROOT_DIR" ]; then
		sysroot_error "${FUNCNAME[0]}: BUILD_SYSROOT_DIR does not exist"
		return 1
	fi

	sysroot_run_commands "$BUILD_SYSROOT_DIR" "$command_string"
}

build_sysroot_run_interactive() {
	if [ ! -d "$BUILD_SYSROOT_DIR" ]; then
		sysroot_error "${FUNCNAME[0]}: BUILD_SYSROOT_DIR does not exist"
		return 1
	fi

	sysroot_run_interactive "$BUILD_SYSROOT_DIR"
}

# shellcheck disable=SC2128
if [ "$0" = "$BASH_SOURCE" ]; then
	sysroot_exit_error 1 "This script needs to be sourced."
fi
