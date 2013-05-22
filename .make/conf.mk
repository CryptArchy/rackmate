ifeq ($(OS),Windows_NT)
  OS = WinNT
  MKDIR = .make\bin\mkdir
  RM = .make\bin\rm
  # We are targeting XP and above, if we don't set this we don't get access to some functions
  CPPFLAGS += -DWINVER=0x0501 -D_WIN32_WINNT=0x0501
  LDFLAGS += -ladvapi32 -lws2_32
daemon: rackmate.exe
else
  MKDIR = mkdir
  ifeq ($(shell uname),Darwin)
    OS = MacOS
  else
    OS = POSIX
  endif
daemon: rackmate
endif


ifdef RELEASE
  ifeq ($(OS),POSIX)
    $(error RELEASE is for Rackit Ltd. If you want to optimize the build specify \
            your own CFLAGS at the TTY and they will override those in this \
            Makefile. eg: CFLAGS='-O3 -march=native' make)
  endif
  CFLAGS = -Oz -g
  CPPFLAGS += -DNDEBUG
  ifeq ($(OS),MacOS)
    CFLAGS += -mmacosx-version-min=10.5 -arch i386 -arch x86_64
    LDFLAGS += -mmacosx-version-min=10.5 -arch i386 -arch x86_64
  endif
  OUTDIR = .make/o/$(OS)-release
  .DEFAULT_GOAL = gui
  GOAL = gui
else
  .DEFAULT_GOAL := daemon
  ifdef MAKECMDGOALS
    GOAL := $(firstword $(MAKECMDGOALS))
  else
    GOAL = daemon
  endif
  ifeq ($(OS),MacOS)
    LDFLAGS += -rpath lib
  endif
endif


OUTDIR ?= .make/o/$(OS)-$(GOAL)
CFLAGS ?= -Os -g
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
    LDFLAGS += -lopenal  #[1]
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


# ^1: we use our own OpenAL because the OS X provided version pops and stutters
