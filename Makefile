ifneq "$(wildcard keys.c)" "keys.c"
  $(error You must create keys.c: see README)
endif

.PHONY: dist-clean clean test macos
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
clean:
	rm -rf $(DIRS) $(OBJS) $(DEPS) Rackmate.app rackmate
dist-clean:
	rm -rf $(filter-out .make/conf.c .make/squish, $(wildcard .make/*)) vendor/underscore vendor/SPMediaKeyTap Rackmate.app rackmate
test:
	@busted -m 'src/?.lua;include/?.lua' spec

.make/%.o: %.c
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(CPPFLAGS) $< $(CFLAGS) -c -o $@
$(OBJS): | $(DIRS)
$(DIRS) .make/include/rackit:
	mkdir -p $@

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

macos: vendor/SPMediaKeyTap $(CNTS)/MacOS/Rackmate $(CNTS)/Info.plist \
       $(CNTS)/Resources/MainMenu.nib $(CNTS)/MacOS/libspotify.dylib \
       $(CNTS)/MacOS/rackmate.lua \
       $(IMGS)

# Carbon is for SPMediaKeyTap, IOKit is for MBInsomnia
$(CNTS)/MacOS/Rackmate: $(SRCS) gui/macos/*.m vendor/SPMediaKeyTap/SPMediaKeyTap.m | $(CNTS)/MacOS
	$(CC) $(CPPFLAGS) -DRACKIT_GUI -Ivendor/SPMediaKeyTap \
		  $(LDFLAGS) -framework Cocoa -framework IOKit -framework Carbon -ObjC -o $@ $^
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
$(CNTS)/MacOS/rackmate.lua: $(filter-out src/main.lua, $(wildcard src/*.lua)) $(wildcard include/*.lua) src/main.lua
	.make/squish $^ > $@

vendor/SPMediaKeyTap:
	git clone https://github.com/rackit/SPMediaKeyTap $@


######################################################################## notes
# * GNU Make sets CC itself if none is set here OR the environment
# * We get cc to generate the header-deps for each .c file and then include
#   that file into this Makefile as it is a makefile-list-of-rules itself
# * The minus in front of the include prevents that rule printing a warning
#   if the DEPS files don't exist, which they won't on the first run.
