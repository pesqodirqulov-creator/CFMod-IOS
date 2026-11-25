# Optional Theos build (equivalent to build.sh, for people who prefer `make`).
#   export THEOS=~/theos
#   make clean all
TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e
DEBUG  := 0
FINALPACKAGE := 1

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := CFMod
CFMod_FILES := $(wildcard src/*.mm src/*.cpp)
CFMod_CFLAGS := -fobjc-arc -Isrc -O2 -fvisibility=hidden -Wno-unused-parameter
CFMod_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore
CFMod_INSTALL_PATH := /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
