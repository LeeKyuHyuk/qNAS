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

clean:
	@rm -rf out

download:
	@wget -c -i wget-list -P $(SOURCES_DIR)
