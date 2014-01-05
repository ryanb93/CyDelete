ARCHS = armv7 armv7s arm64

TARGET = iphone:clang:latest:5.1.1

include theos/makefiles/common.mk

BUNDLE_NAME = cydelete7settings
cydelete7settings_CFLAGS = -fobjc-arc
cydelete7settings_FILES = cydelete7settings.m
cydelete7settings_INSTALL_PATH = /Library/PreferenceBundles
cydelete7settings_FRAMEWORKS = Foundation UIKit
cydelete7settings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/cydelete7settings.plist$(ECHO_END)
