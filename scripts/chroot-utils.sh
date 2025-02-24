#!/usr/bin/env bash

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
	sysroot_do_unmount "$1/dev" -Rl || true
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
	echo "nameserver 8.8.8.8" | sudo tee "${sysroot_dir}/etc/resolv.conf" > /dev/null
	sudo chmod a+rwx "${sysroot_dir}/tmp"

	sysroot_mount_all "$source_dir" "$sysroot_dir"

	sysroot_run_commands \
		"$sysroot_dir" \
		"apt-get update; apt-get -y install $pkglist"
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
