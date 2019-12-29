include settings.mk

.PHONY: all toolchain system kernel image clean

help:
	@$(SCRIPTS_DIR)/help.sh

all:
	@make clean toolchain system kernel image

toolchain:
	@$(SCRIPTS_DIR)/toolchain.sh

system:
	@$(SCRIPTS_DIR)/system.sh

kernel:
	@$(SCRIPTS_DIR)/kernel.sh

image:
	@$(SCRIPTS_DIR)/image.sh

run:
	@qemu-system-x86_64 -kernel $(KERNEL_DIR)/bzImage -drive file=$(IMAGES_DIR)/update/rootfs.ext2,format=raw -append "root=/dev/sda" -redir tcp:8021::21 -redir tcp:9091::9091

clean:
	@rm -rf out

download:
	@wget -c -i wget-list -P $(SOURCES_DIR)
