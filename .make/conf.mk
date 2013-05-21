ifneq ($(OS),Windows_NT)
  ifeq ($(shell uname),Darwin)
    OS = MacOS
  else
    OS = POSIX
  endif
endif

ifdef MAKECMDGOALS
  GOAL := $(firstword $(MAKECMDGOALS))
else
  GOAL = daemon
endif


ifdef RELEASE
  # RELEASE is for Rackit Ltd. not for you, you can specify your own CFLAGS
  # (eg. $ export CFLAGS='-O3 -march=native') and this Makefile will use them
  CFLAGS = -Oz -g
  ifeq ($(OS),MacOS)
    CFLAGS += -mmacosx-version-min=10.5 -arch i386 -arch x86_64
    LDFLAGS += -mmacosx-version-min=10.5 -arch i386 -arch x86_64
  endif
else
  CFLAGS ?= -Os -g
endif


CPPFLAGS += -Iinclude -I.make/include
LDFLAGS += -lspotify
CFLAGS += -std=c99


JSONKit_SRCS = vendor/JSONKit/JSONKit.m
SPMediaKeyTap_SRCS = vendor/SPMediaKeyTap/SPMediaKeyTap.m vendor/SPMediaKeyTap/SPInvocationGrabbing/NSObject+SPInvocationGrabbing.m
UNDERSCORE_SHA = e737917140e555cb8c45f5367e93f11b9ab680cb
LUASRCS := $(wildcard vendor/lua-*/*.c)

$(SPMediaKeyTap_SRCS): vendor/SPMediaKeyTap
$(JSONKit_SRCS): vendor/JSONKit
gui/macos/main.m: $(SPMediaKeyTap_SRCS) $(JSONKit_SRCS)


ifeq ($(GOAL),gui)
  CPPFLAGS += -DRACKMATE_GUI
  LDFLAGS += -Llib
  ifeq ($(OS),MacOS)
    SRCS := $(LUASRCS) $(wildcard src/*.c) $(wildcard gui/macos/*.m) $(SPMediaKeyTap_SRCS) $(JSONKit_SRCS)
    LDFLAGS += -framework Cocoa
    LDFLAGS += -framework Carbon  # SPMediaKeyTap
    LDFLAGS += -framework IOKit  # MBInsomnia
    LDFLAGS += -framework QuartzCore  # MBStatusItemView
    LDFLAGS += -framework Security  # MBWebSocketClient
    CFLAGS += -fno-objc-arc  # support back to OS X 10.4
    CFLAGS += -Wno-deprecated-objc-isa-usage  # JSONKit
    LDFLAGS += -lopenal #[1]
  endif
endif


ifeq ($(GOAL),daemon)
  # you can override this when invoking make
  STANDALONE = 1
  SRCS := $(wildcard src/*.c)
  ifeq ($(STANDALONE),1)
    SRCS += $(LUASRCS)
    LDFLAGS += -Llib -lopenal #[1]
  else
    SRCS += $(wildcard lua-cjson*/*.c)
    LDFLAGS += -llua
    ifeq ($(OS),MacOS)
      LDFLAGS += -framework OpenAL
    else
      LDFLAGS += -lopenal
    endif
  endif

endif


ifndef RELEASE
  OUTDIR := .make/o/$(GOAL)
else
  OUTDIR := .make/oo/$(GOAL)
endif


# ^1: we use our own OpenAL because the OS X provided version pops and stutters
