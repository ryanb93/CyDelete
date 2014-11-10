ARCHS = armv7 arm64

TARGET = iphone:8.1

include theos/makefiles/common.mk

BUNDLE_NAME = Cydelete8
Cydelete8_FILES = Cydelete8ListController.mm
Cydelete8_INSTALL_PATH = /Library/PreferenceBundles
Cydelete8_FRAMEWORKS = Foundation UIKit
Cydelete8_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Cydelete8.plist$(ECHO_END)
