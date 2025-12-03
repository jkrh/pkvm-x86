include core/vars.mk
include platform/$(PLATFORM)/vars.mk

DIRS := kernel qemu

all: $(DIRS)

clean: qemu-clean kernel-clean

$(FETCH_SOURCES):
	@echo "Fetching sources.."
	@git submodule update --init --recursive uefi
	@git submodule update --init

$(TOOLDIR):
	@mkdir -p $(TOOLDIR)

$(BUILD_TOOLS): | $(TOOLDIR) $(FETCH_SOURCES) ; $(build-qemu)

tools: $(BUILD_TOOLS)

tools-clean:
	@rm -rf $(TOOLDIR)

$(OBJDIR): | $(BUILD_TOOLS)
	@mkdir -p $(OBJDIR)

gdb:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) gdb

run:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) run

poorman:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) poorman

clean-vars:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) clean

shim:
	@./scripts/build-shim.sh

# Builds the firmware-open
openfw:
	@./scripts/build-of.sh

# Cleans the uefi variable store(s)
openfw-clean:
	@./scripts/build-of.sh clean

# Runs the build setup
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

qemu: ; $(build-qemu)

qemu-clean:
	@./scripts/build-qemu.sh clean

qemu-distclean:
	@./scripts/build-qemu.sh distclean

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

guestimage:
	@./scripts/create-guestimg.sh $(USER) $(GROUP) -k $(GUEST_KERNEL)

hostimage: $(BUILD_TOOLS)
	@./scripts/create-hostimg.sh $(USER) $(GROUP)

.PHONY: all clean tools tools-clean run gdb poorman kernel kernel-clean \
	kernel-distclean qemu qemu-clean qemu-distclean coreboot \
	target-sysroot target-sysroot-distclean target-qemu target-qemu-clean \
	target-qemu-distclean target-crovm target-coreboot guest-kernel \
	guestimage hostimage $(DIRS)
