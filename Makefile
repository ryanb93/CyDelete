TWEAK_NAME = CyDelete7
CyDelete7_CFLAGS = -fobjc-arc
CyDelete7_FILES = CyDelete7.xm
CyDelete7_FRAMEWORKS = Foundation, UIKit
CyDelete7_LIBRARIES = substrate
CyDelete7_CFLAGS = -fobjc-arc

ARCHS = armv7 armv7s arm64
TARGET = iphone:clang:latest:5.1.1

SUBPROJECTS += setuid cydelete7settings

include theos/makefiles/common.mk

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	find $(FW_STAGING_DIR) -iname '*.plist' -or -iname '*.strings' -exec plutil -convert binary1 {} \;
	find $(FW_STAGING_DIR) -iname '*.png' -exec pincrush -i {} \;
after-install::
	install.exec "killall -9 SpringBoard"
