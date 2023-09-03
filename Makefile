# Detected Variables
CORES := $(shell nproc)
BASE := $(shell pwd)
SYS_ARCH := $(shell uname -p)
SHELL := /bin/bash

# Config Variables
ARCH			= x86
LINUX_DIR		= linux
LINUX_CFG		= $(LINUX_DIR)/.config
BUSYBOX_DIR		= busybox
BUSYBOX_VER     = 1_35_stable
BUSYBOX_CFG		= $(BUSYBOX_DIR)/.config
FILES_DIR		= files
FILESYSTEM_DIR	= filesystem
MOUNT_POINT		= /mnt/disk
INITTAB			= $(FILES_DIR)/inittab
RC				= $(FILES_DIR)/rc
SYSLINUX_CFG	= $(FILES_DIR)/syslinux.cfg
TOOLCHAIN_DIR	= i486-linux-musl-cross
WELCOME			= $(FILES_DIR)/welcome
ROOTFS_SIZE		= 1440

# Generated Files
KERNEL			= bzImage
ROOTFS			= rootfs.cpio.xz
FSIMAGE			= floppinux.img

# Recipe Files
BZIMAGE		= $(LINUX_DIR)/arch/$(ARCH)/boot/$(KERNEL)
INIT		= $(FILESYSTEM_DIR)/sbin/init

.SILENT: download_toolchain

.PHONY: all allconfig rebuild test_filesystem test_floppy_image size clean clean_linux clean_busybox clean_filesystem

linux: get_linux compile_linux

busybox: download_toolchain get_busybox compile_busybox

all: linux busybox make_rootfs make_floppy_image

allconfig: get_linux configure_linux compile_linux download_toolchain get_busybox configure_busybox \
		compile_busybox make_rootfs make_floppy_image

rebuild: clean_filesystem compile_linux compile_busybox make_rootfs make_floppy_image

cleanbuild: clean compile_linux compile_busybox make_rootfs make_floppy_image

get_linux:
ifneq ($(wildcard $(LINUX_DIR)/.git),)
	@echo "Linux directory found, pulling latest changes..."
	cd $(LINUX_DIR) && git pull
else
	@echo "Linux directory not found, cloning repo..."
	git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git $(LINUX_DIR)
	cp $(FILES_DIR)/linux-config $(LINUX_CFG)
endif

configure_linux:
	$(MAKE) ARCH=x86 -C $(LINUX_DIR) mrproper
	$(MAKE) ARCH=x86 -C $(LINUX_DIR) tinyconfig
	$(MAKE) ARCH=x86 -C $(LINUX_DIR) menuconfig

compile_linux:
	$(MAKE) ARCH=x86 -C $(LINUX_DIR) -j $(CORES) $(KERNEL)
	@echo Kernel size
	ls -la $(BZIMAGE)
	cp $(BZIMAGE) ./out

download_toolchain:
ifeq ($(SYS_ARCH),x86_64)
	if [ ! -d $(TOOLCHAIN_DIR) ]; then \
	echo "Downloading musl toolchain..."; \
	wget https://musl.cc/i486-linux-musl-cross.tgz; \
	tar xf i486-linux-musl-cross.tgz; \
	fi
else
	echo "Compiling on i386, toolchain not needed"
endif

get_busybox:
ifneq ($(wildcard $(BUSYBOX_DIR)/.git),)
	@echo "Busybox directory found, pulling latest changes..."
	cd $(BUSYBOX_DIR) && git pull
else
	@echo "Busybox directory not found, cloning repo..."
	git clone -b $(BUSYBOX_VER) https://git.busybox.net/busybox/ $(BUSYBOX_DIR)
	cp $(FILES_DIR)/busybox-config $(BUSYBOX_CFG)
endif

configure_busybox:
	$(MAKE) ARCH=x86 -C $(BUSYBOX_DIR) allnoconfig
	$(MAKE) ARCH=x86 -C $(BUSYBOX_DIR) menuconfig

compile_busybox:
ifeq ($(SYS_ARCH),x86_64)
	@sed -i "s|.*CONFIG_CROSS_COMPILER_PREFIX.*|CONFIG_CROSS_COMPILER_PREFIX="\"$(BASE)"/i486-linux-musl-cross/bin/i486-linux-musl-\"|" $(BUSYBOX_DIR)/.config
	@sed -i "s|.*CONFIG_SYSROOT.*|CONFIG_SYSROOT=\""$(BASE)"/i486-linux-musl-cross\"|" $(BUSYBOX_DIR)/.config
	@sed -i "s|.*CONFIG_EXTRA_CFLAGS.*|CONFIG_EXTRA_CFLAGS=\"-I"$(BASE)"/i486-linux-musl-cross/include\"|" $(BUSYBOX_DIR)/.config
	@sed -i "s|.*CONFIG_EXTRA_LDFLAGS.*|CONFIG_EXTRA_LDFLAGS=\"-L"$(BASE)"/i486-linux-musl-cross/lib\"|" $(BUSYBOX_DIR)/.config
endif
	$(MAKE) ARCH=x86 -C $(BUSYBOX_DIR) -j $(CORES)
	$(MAKE) ARCH=x86 -C $(BUSYBOX_DIR) install
	mv $(BUSYBOX_DIR)/_install $(FILESYSTEM_DIR)

make_rootfs:
	mkdir -p $(FILESYSTEM_DIR)/{dev,proc,etc/init.d,sys,tmp}
	if [ ! -f $(FILESYSTEM_DIR)/dev/console ]; then \
		mknod $(FILESYSTEM_DIR)/dev/console c 5 1; \
	fi
	if [ ! -f $(FILESYSTEM_DIR)/dev/null ]; then \
		mknod $(FILESYSTEM_DIR)/dev/null c 1 3; \
	fi
	cp $(INITTAB) $(FILESYSTEM_DIR)/etc/
	cp $(RC) $(FILESYSTEM_DIR)/etc/init.d/
	cp $(WELCOME) $(FILESYSTEM_DIR)/
	chmod +x $(FILESYSTEM_DIR)/etc/init.d/rc
	chown -R root:root $(FILESYSTEM_DIR)/
	cd $(FILESYSTEM_DIR); find . | cpio -H newc -o | xz --check=crc32 > ../out/$(ROOTFS)

make_floppy_image:
	dd if=/dev/zero of=$(FSIMAGE) bs=1k count=$(ROOTFS_SIZE)
	mkdosfs $(FSIMAGE)
	syslinux --install $(FSIMAGE)
	mkdir -p $(MOUNT_POINT)
	mount -o loop $(FSIMAGE) $(MOUNT_POINT)
	cp out/$(KERNEL) out/$(ROOTFS) $(SYSLINUX_CFG) $(MOUNT_POINT)
	sync
	umount $(MOUNT_POINT)
	mv $(FSIMAGE) ./out

test_filesystem:
	qemu-system-i386 -kernel out/$(KERNEL) -initrd out/$(ROOTFS)

test_floppy_image:
	qemu-system-i386 -fda out/$(FSIMAGE)

size:
	mount -o loop out/$(FSIMAGE) $(MOUNT_POINT)
	df -h $(MOUNT_POINT)
	ls -lah $(MOUNT_POINT)
	umount $(MOUNT_POINT)

clean: clean_linux clean_busybox clean_filesystem

clean_linux:
	$(MAKE) -C $(LINUX_DIR) clean
	rm -f out/$(KERNEL)

clean_busybox:
	$(MAKE) -C $(BUSYBOX_DIR) clean

clean_filesystem:
	rm -rf $(FILESYSTEM_DIR)
	rm -f $(FSIMAGE) $(ROOTFS)

reset: clean_filesystem
	rm -rf $(LINUX_DIR) $(BUSYBOX_DIR) $(TOOLCHAIN_DIR) i486-linux-musl-cross.tgz