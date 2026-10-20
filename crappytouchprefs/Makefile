TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := crappytouchprefs
crappytouchprefs_FILES := CTRootListController.m ../src/Auth.m
crappytouchprefs_FRAMEWORKS := UIKit Security
crappytouchprefs_PRIVATE_FRAMEWORKS := Preferences
crappytouchprefs_INSTALL_PATH := /Library/PreferenceBundles
crappytouchprefs_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
