include vars.mk

QEMU := $(TOOLDIR)/usr/bin/qemu-system-x86_64
VMLINUX := $(KERNEL_DIR)/vmlinux
KERNEL := -kernel $(KERNEL_DIR)/arch/x86_64/boot/bzImage -append '$(KERNEL_OPTS)'
WAYOUT := $(shell exec ip route get 1.1.1.1 | grep -oP 'src \K\S+')
PORT := 10022
MEM := -m 8G

ifeq ($(CLEAN_USB),1)
  $(shell rm -f $(BASE_DIR)/build/usbstick.img)
endif

ifeq ($(UEFI_SHELL),1)
  UEFI_BOOT_APP := ${BASE_DIR}/uefi/firmware-open/edk2/Build/UefiPayloadPkgX64/DEBUG_COREBOOT/X64/Shell.efi
else
  UEFI_BOOT_APP := dummy
endif

# VIRTIO not working yet in the uefi payload, please fix
ifeq ($(OPENFW),1)
KERNEL :=
IMAGE := $(BASE_DIR)/images/host/ubuntuhost-efi.qcow2
# QEMU Q35 model has 16MB firmware limit max or it will overlap with the io-apic
MACHINEOPTS := smm=on,max-fw-size=16M
# SMMSTORE is in the firmware.rom. Remember to clean.
NVRAM := -drive if=pflash,format=raw,unit=0,file=$(BASE_DIR)/build/firmware.rom,readonly=off
USBSTICK := -drive if=none,id=usbdrive,format=raw,file=$(BASE_DIR)/build/usbstick.img \
	-device usb-storage,bus=ehci.0,drive=usbdrive
else ifeq ($(OVMF),1)
KERNEL :=
IMAGE := $(BASE_DIR)/images/host/ubuntuhost-efi.qcow2
# VIRTIO not working yet in the uefi payload, please fix
NVRAM := -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE.fd,readonly=on \
	-drive if=pflash,format=raw,unit=1,file=$(BASE_DIR)/build/OVMF_VARS.fd
else
IMAGE := $(BASE_DIR)/images/host/ubuntuhost.qcow2
DRIVE := -drive file=$(IMAGE),if=virtio,format=qcow2
ifeq ($(BIOS),1)
QEMUOPTS += -bios $(BASE_DIR)/build/coreboot-host.rom
endif
endif

DRIVE := -drive file=$(IMAGE),if=none,id=nvm -device nvme,serial=deadbeef,drive=nvm $(NVRAM)
MACHINE := -machine q35,mem-merge=off,$(MACHINEOPTS) -device intel-iommu,aw-bits=48,device-iotlb=on
CPUFLAGS := +kvm-pv-enforce-cpuid,+vmx,+waitpkg,+ssse3,+tsc,+nx,+x2apic,+hypervisor,$\
	-kvm-pv-ipi,-kvm-pv-tlb-flush,-kvm-pv-unhalt,-kvm-pv-sched-yield,-kvm-asyncpf-int,-kvm-pv-eoi
CPU := --accel kvm,kernel-irqchip=on -cpu host,$(CPUFLAGS) -smp 4 -overcommit cpu-pm=off
USB := -device ich9-usb-ehci1,id=ehci -device usb-kbd $(USBSTICK)
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

$(BASE_DIR)/build/usbstick.img:
	$(BASE_DIR)/scripts/mkusbstickimg.sh $(BASE_DIR)/build/usbstick.img 2048 \
	$(UEFI_BOOT_APP)

run: $(BASE_DIR)/build/usbstick.img
	@echo "------------------------------------------------------------------------------------------"
ifeq ($(GRAPHICS),1)
	@echo "Graphics available at 'spice+unix://$(SPICESOCK)'"
endif
	@echo "Host ssh login is available via $(WAYOUT):$(PORT)"
	@echo "------------------------------------------------------------------------------------------"
	@rm -f $(SPICESOCK)
	echo "Running QEMU.."
	-$(QEMUCMD)
	@cp -rf $(BASE_DIR)/tty2.log $(BASE_DIR)/debug.log

clean:
	@rm -rf $(BASE_DIR)/OVMF_VARS.fd
	@rm -rf $(BASE_DIR)/build/firmware.rom
	@rm -rf $(BASE_DIR)/build/usbstick.img

poorman:
	@PROG=$(KERNEL) BASE_DIR=$(BASE_DIR) VMLINUX=$(VMLINUX) \
		$(BASE_DIR)/scripts/poorman.sh

gdb:
ifeq ($(EDK2DEBUG),1)
	@env EDK2_SOURCE_ROOT_ENV=$(BASE_DIR)/uefi/firmware-open/edk2 \
	EDK2_PLATFORM_PACKAGE_NAME_ENV=UefiPayloadPkgX64 \
	EDK2_BUILD_TARGET_DIR_NAME_ENV=DEBUG_COREBOOT \
	gdb -x $(BASE_DIR)/scripts/gdb-commands -x $(BASE_DIR)/scripts/load_edk2_symbols.py -ex "rebuild-edk2-guidmap $(BASE_DIR)/debug.log"
else
	gdb -x $(BASE_DIR)/scripts/gdb-commands -x $(BASE_DIR)/scripts/load_edk2_symbols.py $(VMLINUX)
endif

.PHONY := gdb clean run poorman
