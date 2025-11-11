ifeq ($(shell echo -e "12.3.0\n$$($${CC} --version 2> /dev/null |grep gcc |awk '{print $$3}')" | awk NF | sort -VC; echo $$?), 1)
$(error "Use gcc 12.3.1 or newer, see GCC bug: 103979.")
endif

export BASE_DIR := $(PWD)
export BASE_BUILD_DIR := $(BASE_DIR)/build
export OBJDIR := $(BASE_DIR)/.objs
export CORE_DIR := $(BASE_DIR)/core
export KERNEL_DIR := $(BASE_DIR)/linux
export QEMUDIR := $(BASE_DIR)/qemu
export TOOLDIR := $(BASE_DIR)/buildtools
export FWOPEN ?= $(BASE_DIR)/uefi/firmware-open

export PATH := $(TOOLDIR)/usr/bin:$(TOOLDIR)/bin:$(PATH)
export LD_LIBRARY_PATH := $(TOOLDIR)/usr/lib:$(TOOLDIR)/usr/local/lib:$(TOOLDIR)/usr/local/lib/x86_64-linux-gnu
export NJOBS := $(shell exec nproc)
export PLATFORM ?= q35
export BUILD_TOOLS := $(TOOLDIR)/usr/bin/qemu-system-x86_64
export FETCH_SOURCES := $(BASE_DIR)/qemu/VERSION
export GROUP := $$(id -gn)
export GUEST_KERNEL ?= $(BASE_DIR)/build/linux

export BUILD_SYSROOT_DIR=$(BASE_DIR)/ubuntu
export UBUNTU_BASE=http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz
export UBUNTU_PKGLIST=$(BASE_DIR)/scripts/package.list.24
export BUILD_WRAPPER=$(BASE_DIR)/scripts/sysroot-wrapper.sh

export QEMU_VARIABLES_WHITELIST=OPENGL SPICE SDL VIRGL DEBUG
export COREBOOT_VARIABLES_WHITELIST=IMAGE_SUFFIX COREBOOT_LINUX_CMDLINE
