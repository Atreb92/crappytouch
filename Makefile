THEOS ?= $(HOME)/theos
TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
# Fedora: no lzma binary (dpkg on the phone reads xz), and fakeroot's default tcp backend is blocked
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := xz
export PATH := $(CURDIR)/scripts/bin:$(PATH)
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := crappytouch
crappytouch_FILES := Tweak.x src/Server.m src/Auth.m src/Pairing.m src/Touch.m src/Keyboard.m src/Clipboard.m src/Screen.m src/Apps.m src/Awake.m
crappytouch_FRAMEWORKS := Security UIKit IOKit
crappytouch_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
