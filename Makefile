ifneq "$(wildcard keys.c)" "keys.c"
  $(error You must create keys.c: see README)
endif

CPPFLAGS += -Iinclude -I.make/include
CFLAGS ?= -O0 -g
LDFLAGS += -Llib -lspotify
UNDERSCORE_SHA = 36bde133d0ffc618dc19a05b918a4d0bc6343cb6


####################################################################### daemon
SRCS := $(shell find src -name \*.c) $(shell find vendor -name \*.c)
OBJS = $(patsubst %.c, .make/%.o, $(SRCS))

ifeq "$(shell uname)" "Darwin"
	LDFLAGS += -framework OpenAL -framework Security
endif

rackmate: .make/include/rackit/conf.h $(OBJS) .make/$(UNDERSCORE_SHA)
	$(CC) $(LDFLAGS) $(OBJS) -o $@


#################################################################### configure
.make/conf: .make/conf.c
	$(CC) $(CPPFLAGS) $< -o $@
.make/include/rackit/conf.h: .make/conf include/luaconf.h | .make/include/rackit
	$< > $@


#################################################################### gui:macos
MACOS_SRCS := $(wildcard gui/macos/*.m) vendor/JSONKit/JSONKit.m vendor/SPMediaKeyTap/SPMediaKeyTap.m vendor/SPMediaKeyTap/SPInvocationGrabbing/NSObject+SPInvocationGrabbing.m
MACOS_OBJS = $(patsubst %.c, .make/macos/%.o, $(SRCS)) $(patsubst %.m, .make/macos/%.o, $(MACOS_SRCS))
MACOS_CPPFLAGS = $(CPPFLAGS) -DRACKIT_GUI
MACOS_CFLAGS = $(CFLAGS) -fno-objc-arc -Wno-deprecated-objc-isa-usage
#to quieten:                            JSONKit
MACOS_LDFLAGS = -framework Carbon -framework IOKit -framework Cocoa $(LDFLAGS) $(CPPFLAGS)
#to satisfy:               SPMediaKeyTap     MBInsomnia

macos: Rackmate.app/Contents/MacOS/rackmate.lua \
       Rackmate.app/Contents/MacOS/Rackmate \
       Rackmate.app/Contents/Info.plist \
       Rackmate.app/Contents/Resources/MainMenu.nib \
       Rackmate.app/Contents/MacOS/libspotify.dylib \
       $(patsubst gui/macos/%.png, Rackmate.app/Contents/Resources/%.png, $(wildcard gui/macos/*.png))

Rackmate.app/Contents/MacOS/Rackmate: vendor/SPMediaKeyTap vendor/JSONKit .make/include/rackit/conf.h $(MACOS_OBJS) | Rackmate.app/Contents/MacOS
	$(CC) $(MACOS_LDFLAGS) $(MACOS_OBJS) -o $@
	xcrun install_name_tool -change @rpath/libspotify.dylib @executable_path/libspotify.dylib $@
Rackmate.app/Contents/Info.plist: gui/macos/Info.plist
	cp $< $@
Rackmate.app/Contents/Resources/MainMenu.nib: gui/macos/MainMenu.xib | Rackmate.app/Contents/Resources
	ibtool --output-format binary1 --compile $@ $<
Rackmate.app/Contents/MacOS/libspotify.dylib: lib/libspotify.dylib
	cp $< $@
Rackmate.app/Contents/Resources/%.png: gui/macos/%.png
	cp $< $@
Rackmate.app/Contents/MacOS/rackmate.lua: $(filter-out src/main.lua, $(wildcard src/*.lua)) $(wildcard include/*.lua) src/main.lua | Rackmate.app/Contents/MacOS .make/$(UNDERSCORE_SHA)
	.make/squish $^ > $@


################################################################## directories
DIRS = $(sort $(dir $(OBJS))) $(sort $(dir $(MACOS_OBJS))) .make/include/rackit Rackmate.app/Contents/MacOS Rackmate.app/Contents/Resources
$(OBJS) $(MACOS_OBJS): | $(DIRS)
$(DIRS):
	mkdir -p $@


######################################################################## PHONY
.PHONY: dist-clean clean test macos

clean:
	rm -rf $(DIRS) $(MACOS_OBJS) $(OBJS) $(DEPS) Rackmate.app rackmate
dist-clean:
	rm -rf $(filter-out .make/conf.c .make/squish, $(wildcard .make/*)) vendor/underscore vendor/SPMediaKeyTap vendor/JSONKit Rackmate.app rackmate
test:
	@busted -m 'src/?.lua;include/?.lua' spec


########################################################################## %.d
DEPS = $(OBJS:.o=.d) $(MACOS_OBJS:.o=.d)
-include $(DEPS)


####################################################################### vendor
.make/$(UNDERSCORE_SHA): vendor/underscore
	git --git-dir=$^/.git --work-tree=$^ reset --hard $(@F) > $@
vendor/underscore:
	git clone https://github.com/rackit/underscore.lua $@
vendor/SPMediaKeyTap:
	git clone https://github.com/rackit/SPMediaKeyTap $@
vendor/JSONKit:
	git clone https://github.com/johnezang/JSONKit $@

#################################################################### implicits
.make/%.o: %.c
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(CPPFLAGS) $< $(CFLAGS) -c -o $@
.make/macos/%.o: %.m
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(MACOS_CPPFLAGS) $< $(MACOS_CFLAGS) -c -o $@
.make/macos/%.o: %.c
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(MACOS_CPPFLAGS) $< $(CFLAGS) -c -o $@


######################################################################## notes
# * GNU Make sets CC itself if none is set here OR the environment
# * We get cc to generate the header-deps for each .c file and then include
#   that file into this Makefile as it is a makefile-list-of-rules itself
# * The minus in front of the include prevents that rule printing a warning
#   if the DEPS files don't exist, which they won't on the first run.
