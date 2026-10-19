THEOS ?= $(HOME)/theos
TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
# Fedora: no lzma binary (dpkg on the phone reads xz), and fakeroot's default tcp backend is blocked
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := xz
export PATH := $(CURDIR)/scripts/bin:$(PATH)
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := scrcrappyagent
scrcrappyagent_FILES := Tweak.x src/Server.m src/Auth.m src/Pairing.m
scrcrappyagent_FRAMEWORKS := Security UIKit
scrcrappyagent_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
