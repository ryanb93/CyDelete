TOOL_NAME := setuid
setuid_C_FILES = setuid.c
setuid_PACKAGE_TARGET_DIR = /usr/libexec/cydelete

ARCHS = armv7 arm64

include ../theos/makefiles/common.mk
include ../theos/makefiles/tool.mk

after-setuid-stage::
	sudo chmod 4755 $(FW_STAGING_DIR)/usr/libexec/cydelete/setuid
	sudo chown root:wheel $(FW_STAGING_DIR)/usr/libexec/cydelete/setuid
