#!/bin/sh -e

export PATH=$PWD:$PATH
export IMAGE="${IMAGE:-ubuntuguest.qcow2}"
export KERNEL="${KERNEL:-bzImage}"
export RAM=4096
export CORECOUNT=2

[ ! -d /var/empty ] && mkdir /var/empty
[ "x$DEBUG" != "x" ] && DEBUG='--gdb 1234' && KERNEL=vmlinux && CORECOUNT=1

if [ ! -d /sys/class/net/crosvm_tap ]; then
        ip tuntap add mode tap user $USER vnet_hdr crosvm_tap
        ip addr add 192.168.8.1/24 dev crosvm_tap
        ip link set crosvm_tap up

        sysctl net.ipv4.ip_forward=1
        # Network interface used to connect to the internet.
        HOST_DEV=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
        iptables -t nat -A POSTROUTING -o "${HOST_DEV}" -j MASQUERADE
        iptables -A FORWARD -i "${HOST_DEV}" -o crosvm_tap -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -i crosvm_tap -o "${HOST_DEV}" -j ACCEPT
fi

${CROSVM:-crosvm} --log-level=debug run $DEBUG $KERNEL --cpus num-cores=$CORECOUNT		\
	--mem size=$RAM --block path=$IMAGE --net tap-name=crosvm_tap	\
	--serial type=stdout,hardware=virtio-console,console,stdin		\
	--core-scheduling false \
	-p "root=/dev/vda1 rw" \
	--protected-vm-without-firmware
