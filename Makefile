include core/vars.mk
include platform/$(PLATFORM)/vars.mk

DIRS := kernel guest-kernel qemu

all: $(DIRS)

clean: qemu-clean kernel-clean

$(FETCH_SOURCES):
	@echo "Fetching sources.."
	@git submodule update --init --recursive uefi
	@git submodule update --init

$(TOOLDIR):
	@mkdir -p $(TOOLDIR)

$(BUILD_TOOLS): | $(TOOLDIR) $(FETCH_SOURCES)

tools: $(BUILD_TOOLS)

tools-clean:
	@rm -rf $(TOOLDIR)

$(OBJDIR): | $(BUILD_TOOLS)
	@mkdir -p $(OBJDIR)

#
# Attach to a debugger started by 'DEBUGGER=1 run' target. Symbols
# to load can be specified via EDK2DEBUG=1 or SHIMDEBUG=1. Kernel
# symbols are the default.
#
gdb:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) gdb

run: $(HOST_QEMU)
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) run

poorman:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) poorman

# Cleans the emulation uefi variable store(s)
clean-vars:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) clean

# Generates the shim and signing keys
$(SHIM):
	@./scripts/build-shim.sh

# Builds the firmware-open at FWOPEN=<dir>
openfw: $(SHIM)
	@./scripts/build-of.sh

# Cleans the firmware-open build at FWOPEN=<dir>
openfw-clean:
	@./scripts/build-of.sh clean

# Runs the firmware-open build setup at FWOPEN=<dir>
openfw-setup:
	@./scripts/build-of.sh setup

kernel:
	@cp scripts/nixos_* $(KERNEL_DIR)/arch/x86/configs/
	$(MAKE) CC="$(CC)" -C$(KERNEL_DIR) -j$(NJOBS) nixos_defconfig bzImage modules

kernel-clean:
	$(MAKE) CC="$(CC)" -C$(KERNEL_DIR) -j$(NJOBS) mrproper

kernel-distclean:
	cd $(KERNEL_DIR); git xlean -xfd

build-qemu = @./scripts/build-qemu.sh build

$(HOST_QEMU): ; $(build-qemu)

qemu: $(HOST_QEMU)

qemu-clean:
	@./scripts/build-qemu.sh clean

qemu-distclean:
	@./scripts/build-qemu.sh distclean

# Isolated coreboot for testing - note that OVMF and OPENFW targets use their own
coreboot: kernel
	@IMAGE_SUFFIX=host COREBOOT_LINUX_CMDLINE="$(KERNEL_OPTS)" ./scripts/build-coreboot.sh \
		scripts/q35_defconfig \
		linux/arch/x86_64/boot/bzImage

target-sysroot:
	@./scripts/create-sysroot.sh

target-sysroot-distclean:
	@./scripts/create-sysroot.sh distclean

target-qemu:
	@DEBUG=1 $(BUILD_WRAPPER) ./scripts/build-target-qemu.sh

target-qemu-clean:
	@$(BUILD_WRAPPER) ./scripts/build-target-qemu.sh clean

target-qemu-distclean:
	@$(BUILD_WRAPPER) ./scripts/build-target-qemu.sh distclean

target-crosvm:
	@$(BUILD_WRAPPER) ./scripts/build-target-crosvm.sh

target-coreboot: guest-kernel
	@IMAGE_SUFFIX=guest $(BUILD_WRAPPER) ./scripts/build-coreboot.sh \
		scripts/q35_guest_defconfig linux/arch/x86_64/boot/bzImage

guest-kernel:
	@CC="$(CC)" ./scripts/build-guest-kernel.sh

# Generate an ubuntu test image(s). Set EFI=1 to make a full UEFI setup.
guestimage: $(SHIM) guest-kernel
	@./scripts/create-guestimg.sh $(USER) $(GROUP) -k $(GUEST_KERNEL)

hostimage: $(BUILD_TOOLS) $(SHIM) kernel
	@./scripts/create-hostimg.sh $(USER) $(GROUP)

.PHONY: all clean tools tools-clean run gdb poorman kernel kernel-clean \
	kernel-distclean qemu qemu-clean qemu-distclean coreboot \
	target-sysroot target-sysroot-distclean target-qemu target-qemu-clean \
	target-qemu-distclean target-crovm target-coreboot guest-kernel \
	guestimage hostimage $(DIRS)
