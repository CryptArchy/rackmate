ifneq "$(wildcard keys.c)" "keys.c"
  $(error You must create keys.c: see README)
endif

SRCS := $(shell find src -name \*.c) $(shell find vendor -name \*.c)
OBJS = $(patsubst %.c, .make/%.o, $(SRCS))
DEPS = $(OBJS:.o=.d)
DIRS = $(sort $(dir $(OBJS)))
CPPFLAGS += -Iinclude -I.make/include
CFLAGS ?= -O0 -g
LDFLAGS += -Llib -lspotify

UNDERSCORE_SHA = 31b3b537b9f849dc854d0b528412321daf7eab8a

ifeq "$(shell uname)" "Darwin"
	LDFLAGS += -framework OpenAL -framework Security
endif

rackmate: .make/include/rackit/conf.h $(OBJS) .make/$(UNDERSCORE_SHA)
	$(CC) $(LDFLAGS) $(OBJS) -o $@

$(OBJS): | $(DIRS)

.make/conf: .make/conf.c
	$(CC) $(CPPFLAGS) $< -o $@
.make/include/rackit/conf.h: .make/conf include/luaconf.h | .make/include/rackit
	$< > $@

-include $(DEPS)

.make/$(UNDERSCORE_SHA): vendor/underscore
	git --git-dir=$^/.git --work-tree=$^ reset --hard $(@F) > $@
vendor/underscore:
	git clone https://github.com/rackit/underscore.lua $@


#################################################################### gui:macos
CNTS := Rackmate.app/Contents
LUAS := $(wildcard src/*.lua) $(wildcard include/*.lua)
IMGS := $(patsubst gui/macos/%.png, $(CNTS)/Resources/%.png, $(wildcard gui/macos/*.png))

MACOS_SRCS := $(wildcard gui/macos/*.m) $(wildcard vendor/UnittWebSocketClient/*.m) vendor/JSONKit/JSONKit.m vendor/SPMediaKeyTap/SPMediaKeyTap.m
MACOS_OBJS = $(patsubst %.c, .make/macos/%.o, $(SRCS)) $(patsubst %.m, .make/macos/%.o, $(MACOS_SRCS))
MACOS_DIRS = $(sort $(dir $(MACOS_OBJS)))
MACOS_DEPS = $(MACOS_OBJS:.o=.d)

MACOS_CFLAGS = $(CFLAGS) -fno-objc-arc -Wno-deprecated-objc-isa-usage
#to quieten:                            JSONKit
MACOS_LDFLAGS = -framework Carbon -framework IOKit -framework Cocoa $(LDFLAGS) $(CPPFLAGS)
#to satisfy:               SPMediaKeyTap     MBInsomnia
MACOS_CPPFLAGS = $(CPPFLAGS) -DRACKIT_GUI

macos: vendor/SPMediaKeyTap vendor/JSONKit .make/$(UNDERSCORE_SHA) \
	   $(CNTS)/MacOS/rackmate.lua \
       $(CNTS)/MacOS/Rackmate \
       $(CNTS)/Info.plist \
       $(CNTS)/Resources/MainMenu.nib \
       $(CNTS)/MacOS/libspotify.dylib \
       $(IMGS)

$(MACOS_OBJS): | $(MACOS_DIRS)

$(CNTS)/MacOS/Rackmate: $(MACOS_OBJS) .make/include/rackit/conf.h | $(CNTS)/MacOS
	$(CC) $(MACOS_LDFLAGS) $(MACOS_OBJS) -o $@
	xcrun install_name_tool -change @rpath/libspotify.dylib @executable_path/libspotify.dylib $(CNTS)/MacOS/Rackmate
$(CNTS)/Info.plist: gui/macos/Info.plist
	cp $< $@
$(CNTS)/Resources/MainMenu.nib: gui/macos/MainMenu.xib | $(CNTS)/Resources
	ibtool --output-format human-readable-text --compile $@ $<
$(CNTS)/MacOS $(CNTS)/Resources:
	mkdir -p $@
$(CNTS)/MacOS/libspotify.dylib: lib/libspotify.dylib
	cp $< $@
$(CNTS)/Resources/%.png: gui/macos/%.png
	cp $< $@
$(CNTS)/MacOS/rackmate.lua: $(filter-out src/main.lua, $(wildcard src/*.lua)) $(wildcard include/*.lua) src/main.lua | $(CNTS)/MacOS
	.make/squish $^ > $@
vendor/SPMediaKeyTap:
	git clone https://github.com/rackit/SPMediaKeyTap $@
vendor/JSONKit:
	git clone https://github.com/johnezang/JSONKit $@

-include $(MACOS_DEPS)


###################################################################### general
$(DIRS) $(MACOS_DIRS) .make/include/rackit:
	mkdir -p $@


######################################################################## PHONY
.PHONY: dist-clean clean test macos

clean:
	rm -rf $(DIRS) $(MACOS_DIRS) $(MACOS_OBJS) $(OBJS) $(DEPS) Rackmate.app rackmate
dist-clean:
	rm -rf $(filter-out .make/conf.c .make/squish, $(wildcard .make/*)) vendor/underscore vendor/SPMediaKeyTap vendor/JSONKit Rackmate.app rackmate
test:
	@busted -m 'src/?.lua;include/?.lua' spec


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
