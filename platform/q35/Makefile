include vars.mk

QEMU := $(TOOLDIR)/usr/bin/qemu-system-x86_64
VMLINUX := $(KERNEL_DIR)/vmlinux
KERNEL := -kernel $(KERNEL_DIR)/arch/x86_64/boot/bzImage -append '$(KERNEL_OPTS)'
WAYOUT := $(shell exec ip route get 1.1.1.1 | grep -oP 'src \K\S+')
PORT := 10022
MACHINE := -machine q35,mem-merge=off -device intel-iommu,aw-bits=48,device-iotlb=on
MEM := -m 8G

ifeq ($(OPENFW),1)
KERNEL :=
IMAGE := $(BASE_DIR)/images/host/ubuntuhost-efi.qcow2
# VIRTIO not working yet in the uefi payload, please fix
NVRAM := -bios $(BASE_DIR)/build/firmware.rom
DRIVE := -device ich9-ahci,id=ahci \
	-drive file=$(IMAGE),if=none,id=disk0,format=qcow2 \
	-device ide-hd,drive=disk0,bus=ahci.0 \
	$(NVRAM)
endif

ifeq ($(OVMF),1)
KERNEL :=
IMAGE := $(BASE_DIR)/images/host/ubuntuhost-efi.qcow2
# VIRTIO not working yet in the uefi payload, please fix
NVRAM := -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE.fd,readonly=on \
	-drive if=pflash,format=raw,unit=1,file=$(BASE_DIR)/OVMF_VARS.fd
DRIVE := -device ich9-ahci,id=ahci \
	-drive file=$(IMAGE),if=none,id=disk0,format=qcow2 \
	-device ide-hd,drive=disk0,bus=ahci.0 \
	$(NVRAM)
endif

ifeq ($(KERNEL),'')
IMAGE := $(BASE_DIR)/images/host/ubuntuhost.qcow2
DRIVE := -drive file=$(IMAGE),if=virtio,format=qcow2
ifeq ($(BIOS),1)
QEMUOPTS += -bios $(BASE_DIR)/build/coreboot-host.rom
endif
endif

CPUFLAGS := +kvm-pv-enforce-cpuid,+vmx,+waitpkg,+ssse3,+tsc,+nx,+x2apic,+hypervisor,$\
	-kvm-pv-ipi,-kvm-pv-tlb-flush,-kvm-pv-unhalt,-kvm-pv-sched-yield,-kvm-asyncpf-int,-kvm-pv-eoi
CPU := --accel kvm,kernel-irqchip=on -cpu host,$(CPUFLAGS) -smp 4 -overcommit cpu-pm=off
USB := -device qemu-xhci -device usb-kbd
NETWORK := -device e1000,netdev=net0 -netdev user,id=net0,host=192.168.7.1,net=192.168.7.0/24,restrict=off,hostname=guest,hostfwd=tcp:$(WAYOUT):$(PORT)-192.168.7.2:22

SPICESOCK := /tmp/host
VDAGENT := -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
SPICEOPTS := unix=on,addr=$(SPICESOCK),disable-ticketing=on,image-compression=off,streaming-video=all,playback-compression=off,disable-agent-file-xfer=off

ifeq ($(DEBUGMMU),1)
QEMUDEBUGOPTS := guest_errors,unimp,mmu
else
QEMUDEBUGOPTS := guest_errors,unimp
endif
QEMUDEBUGLOG := -D $(BASE_DIR)/qemudebug.log

QEMUOPTS := $(MACHINE) $(CPU) $(MEM) $(DRIVE) $(NETWORK) $(USB) $(KERNEL) \
	-d $(QEMUDEBUGOPTS) $(QEMUDEBUGLOG) $(QEMUTRACEOPTS) $(DEBUGOPTS)

ifeq ($(DEBUGGER),1)
QEMUOPTS := $(QEMUOPTS) -S -s
endif

ifeq ($(QEMUDEBUG),1)
QEMUCMD := gdb $(QEMU)-debug -ex "r $(QEMUOPTS) -serial stdio -display none"
else
QEMUCMD := $(QEMU) $(QEMUOPTS) -nographic
endif

ifeq ($(OPENFW),1)
QEMUCMD := $(QEMU) $(QEMUOPTS) \
	   -chardev stdio,id=debugcon,mux=on -device isa-debugcon,iobase=0x402,chardev=debugcon \
	   -serial file:$(BASE_DIR)/tty0.log -serial file:$(BASE_DIR)/tty1.log -serial file:$(BASE_DIR)/tty2.log
endif

ifeq ($(GRAPHICS),1)
QEMUCMD := $(QEMUCMD) -device virtio-gpu-gl-pci,id=gpu0 -display egl-headless -spice $(SPICEOPTS) $(VDAGENT)
endif

run:
	@echo "------------------------------------------------------------------------------------------"
ifeq ($(GRAPHICS),1)
	@echo "Graphics available at 'spice+unix://$(SPICESOCK)'"
endif
	@echo "Host ssh login is available via $(WAYOUT):$(PORT)"
	@echo "------------------------------------------------------------------------------------------"
	@rm -f $(SPICESOCK)
	@if [ ! -e $(BASE_DIR)/OVMF_VARS.fd ] ; then cp /usr/share/OVMF/OVMF_VARS.fd $(BASE_DIR); fi
	@echo "Running QEMU.."
	$(QEMUCMD)

poorman:
	@PROG=$(KERNEL) BASE_DIR=$(BASE_DIR) VMLINUX=$(VMLINUX) \
		$(BASE_DIR)/scripts/poorman.sh

gdb:
	@gdb -x $(BASE_DIR)/scripts/gdb-commands $(VMLINUX)
