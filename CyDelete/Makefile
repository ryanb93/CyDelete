ARCHS = armv7 arm64

TARGET = iphone:8.1

include theos/makefiles/common.mk

BUNDLE_NAME = CyDelete
CyDelete_FILES = CyDeleteListController.mm
CyDelete_INSTALL_PATH = /Library/PreferenceBundles
CyDelete_FRAMEWORKS = Foundation UIKit
CyDelete_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CyDelete.plist$(ECHO_END)
