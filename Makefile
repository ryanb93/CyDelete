ARCHS = armv7 arm64
TARGET = iphone:8.1

include theos/makefiles/common.mk

TWEAK_NAME = CyDelete8
CyDelete8_FILES = CyDelete8.xm
CyDelete8_FRAMEWORKS = Foundation, UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += setuid CyDelete8
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
