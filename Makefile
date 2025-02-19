include core/vars.mk

DIRS := kernel qemu

all: $(DIRS)

clean: qemu-clean kernel-clean

$(FETCH_SOURCES):
	@echo "Fetching sources.."
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
	@sudo -E chmod +666 /dev/kvm
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) run

poorman:
	$(MAKE) KERNEL_DIR=$(KERNEL_DIR) -Cplatform/$(PLATFORM) poorman

kernel:
	@cp scripts/nixos_* $(KERNEL_DIR)/arch/x86/configs/
	$(MAKE) CC=$(CC) -C$(KERNEL_DIR) -j$(NJOBS) nixos_defconfig bzImage modules

kernel-clean:
	$(MAKE) CC=$(CC) -C$(KERNEL_DIR) -j$(NJOBS) mrproper

kernel-distclean:
	cd $(KERNEL_DIR); git xlean -xfd

build-qemu = @./scripts/build-qemu.sh build

qemu: ; $(build-qemu)

qemu-clean:
	@./scripts/build-qemu.sh clean

qemu-distclean:
	@./scripts/build-qemu.sh distclean

target-sysroot:
	@./scripts/create-sysroot.sh

target-sysroot-distclean:
	@./scripts/create-sysroot.sh distclean

target-qemu:
	@DEBUG=1 ./scripts/build-target-qemu.sh

target-qemu-clean:
	@./scripts/build-target-qemu.sh clean

target-qemu-distclean:
	@./scripts/build-target-qemu.sh distclean

target-crosvm:
	@./scripts/build-target-crosvm.sh

guest-kernel:
	@./scripts/build-guest-kernel.sh

guestimage:
	@sudo -E ./scripts/create_guestimg.sh $(USER) $(GROUP) -k $(GUEST_KERNEL)

hostimage: $(BUILD_TOOLS)
	@sudo -E ./scripts/create_hostimg.sh $(USER) $(GROUP)

coreboot-guest: guest-kernel
	@./scripts/build-coreboot.sh -g

coreboot-host: kernel
	@./scripts/build-coreboot.sh -e

.PHONY: all clean target-qemu run $(DIRS)
