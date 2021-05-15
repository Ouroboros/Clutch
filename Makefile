FINALPACKAGE := 1
DEBUG ?= 0

export THEOS_DEVICE_IP = 127.0.0.1
export THEOS_DEVICE_PORT = 2222
export THEOS_BUILD_DIR = build
SDKVERSION = 9.2

include $(THEOS)/makefiles/common.mk

ARCHS = arm64

ADDITIONAL_CFLAGS += -fobjc-arc -Werror -Wno-c++11-compat-deprecated-writable-strings -Wno-deprecated-declarations -Wno-macro-redefined
ADDITIONAL_CFLAGS += -Wno-nullability-completeness-on-arrays -Wno-writable-strings -Wno-c++11-narrowing
ADDITIONAL_CFLAGS += -Wno-unused-variable -Wno-unused-function -Wno-unused-value -Wno-c++11-compat-deprecated-writable-strings
ADDITIONAL_CFLAGS += -Wno-unused-command-line-argument
ADDITIONAL_CFLAGS += -fno-rtti -fvisibility=hidden

ADDITIONAL_LDFLAGS += -L. -Wl,-segalign,4000 -Wl,-dead_strip -read_only_relocs suppress

LIBRARIES = z substrate
FRAMEWORKS = MobileCoreServices
PRIVATE_FRAMEWORKS =

TOOL_NAME = Clutch
Clutch_CODESIGN_FLAGS = --ent src/Clutch.entitlements
Clutch_LIBRARIES = $(LIBRARIES)
Clutch_FRAMEWORKS = $(FRAMEWORKS)
Clutch_PRIVATE_FRAMEWORKS = $(PRIVATE_FRAMEWORKS)

Clutch_FILES = \
	$(wildcard src/*.mm) \
	$(wildcard src/*.m) \
	$(wildcard src/MiniZip/*.c) \

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	rm -rf *.deb $(THEOS_STAGING_DIR)

after-uninstall::

after-clean::
	rm -rf ./build/ ./.theos