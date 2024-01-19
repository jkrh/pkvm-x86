QEMU := qemu-system-x86_64
KERNEL := $(KERNEL_DIR)/arch/x86_64/boot/bzImage
VMLINUX := $(KERNEL_DIR)/vmlinux
IMAGE := $(BASE_DIR)/images/host/ubuntuhost.qcow2

#KERNEL_OPTS := root=/dev/vda1 console=ttyS0 mem=8G swiotlb=force nokaslr loglevel=8 intel_iommu=sm_on rw
KERNEL_OPTS := root=/dev/vda1 console=ttyS0 mem=8G swiotlb=force nokaslr loglevel=8 intel_iommu=on rw
WAYOUT := $(shell exec ip route get 1.1.1.1 | grep -oP 'src \K\S+')
PORT := 10022
MACHINE := -machine q35 -device intel-iommu,aw-bits=48,device-iotlb=on
MEM := -m 8G
CPUFLAGS := +kvm-pv-enforce-cpuid,+vmx,+waitpkg,+tsc,+nx,+kvm-pv-ipi,+kvm-pv-tlb-flush,+kvm-pv-sched-yield,+kvm-asyncpf-int
CPU := --enable-kvm -cpu host,$(CPUFLAGS) -smp 4
DRIVE := -drive file=$(IMAGE),if=virtio,format=qcow2
USB := -device qemu-xhci -device usb-kbd
NETWORK := -device e1000,netdev=net0 -netdev user,id=net0,host=192.168.7.1,net=192.168.7.0/24,restrict=off,hostname=guest,hostfwd=tcp:$(WAYOUT):$(PORT)-192.168.7.2:22

SPICESOCK := /tmp/host
VDAGENT := -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
SPICEOPTS := unix=on,addr=$(SPICESOCK),disable-ticketing=on,image-compression=off,streaming-video=all,playback-compression=off,disable-agent-file-xfer=off

#QEMUTRACEOPTS := --trace "virtio_blk*" --trace "virtio_notify" --trace "virtio_set_status" --trace "virtio_queue_notify"
QEMUDEBUGOPTS :=

ifeq ($(DEBUGMMU),1)
QEMUDEBUGOPTS := guest_errors,unimp,mmu
else
QEMUDEBUGOPTS := guest_errors,unimp
endif
QEMUDEBUGLOG := -D $(BASE_DIR)/qemudebug.log

QEMUOPTS := $(MACHINE) $(CPU) $(MEM) $(DRIVE) $(NETWORK) $(USB) -d $(QEMUDEBUGOPTS) \
	$(QEMUDEBUGLOG) $(QEMUTRACEOPTS) $(DEBUGOPTS) -kernel $(KERNEL) -append '$(KERNEL_OPTS)'

ifeq ($(DEBUGGER),1)
QEMUOPTS := $(QEMUOPTS) -S -s
endif

ifeq ($(QEMUDEBUG),1)
QEMUCMD := gdb $(QEMU)-debug -ex "r $(QEMUOPTS) -serial stdio -display none"
else
QEMUCMD := $(QEMU) $(QEMUOPTS) -nographic
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
	@echo "Running QEMU.."
	@$(QEMUCMD)

poorman:
	@PROG=$(KERNEL) BASE_DIR=$(BASE_DIR) VMLINUX=$(VMLINUX) \
		$(BASE_DIR)/scripts/poorman.sh

gdb:
	@gdb -ex "target remote localhost:1234" -ex "set confirm off" $(VMLINUX)
