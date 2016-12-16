ARCHS = armv7 arm64
TARGET = iphone

include theos/makefiles/common.mk

TWEAK_NAME = CyDelete
CyDelete_FILES = CyDelete.xm
CyDelete_FRAMEWORKS = Foundation, UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += setuid CyDelete
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall backboardd"
