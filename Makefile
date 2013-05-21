ifneq "$(wildcard keys.c)" "keys.c"
  $(error You must create keys.c: see README)
endif

include .make/conf.mk

OBJS := $(filter %.o, $(patsubst %.c, $(OUTDIR)/%.o, $(SRCS)) $(patsubst %.m, $(OUTDIR)/%.o, $(SRCS)))
LUA := $(wildcard include/*.lua) $(filter-out src/main.lua, $(wildcard src/*.lua)) src/main.lua


###################################################################### targets
daemon: $(OBJS)
	$(CC) $(LDFLAGS) -rpath lib $^ -o rackmate

ifeq ($(OS),MacOS)
gui: Rackmate.app/Contents/MacOS/Rackmate \
     Rackmate.app/Contents/Info.plist \
     Rackmate.app/Contents/MacOS/libspotify.dylib \
     Rackmate.app/Contents/MacOS/libopenal.dylib \
     $(patsubst gui/macos/%.png, Rackmate.app/Contents/Resources/%.png, $(wildcard gui/macos/*.png))
endif

Rackmate.app/Contents/MacOS/Rackmate: $(OBJS) Rackmate.app/Contents/MacOS/libopenal.dylib Rackmate.app/Contents/MacOS/libspotify.dylib | Rackmate.app/Contents/MacOS
	$(CC) $(LDFLAGS) $^ -o $@
	xcrun install_name_tool -change @rpath/libspotify.dylib @executable_path/libspotify.dylib $@
	xcrun install_name_tool -change @rpath/libopenal.dylib @executable_path/libopenal.dylib $@
Rackmate.app/Contents/MacOS/libspotify.dylib: lib/libspotify.dylib | Rackmate.app/Contents/MacOS
	cp $< $@
Rackmate.app/Contents/MacOS/libopenal.dylib: lib/libopenal.dylib | Rackmate.app/Contents/MacOS
	cp $< $@
Rackmate.app/Contents/Info.plist: gui/macos/Info.plist | Rackmate.app/Contents
	cp $< $@
Rackmate.app/Contents/Resources/%.png: gui/macos/%.png | Rackmate.app/Contents/Resources
	cp $< $@

$(OBJS): .make/include/rackit/conf.h
src/main.c: .make/include/rackmate.lua.h

.make/include/rackmate.lua.h: $(LUA) .make/$(UNDERSCORE_SHA) .make/squish | .make/include
	.make/squish $(LUA) > $@


#################################################################### configure
.make/conf: .make/conf.c
	$(CC) $(CPPFLAGS) $< -o $@
.make/include/rackit/conf.h: .make/conf include/luaconf.h | .make/include/rackit
	$< > $@


########################################################################## etc
.PHONY: dist-clean clean test gui daemon
.DELETE_ON_ERROR:
.DEFAULT_GOAL := daemon

clean:
	rm -rf .make/o .make/oo Rackmate.app rackmate .make/include/rackmate.lua.h
dist-clean:
	rm -rf .make/o .make/oo .make/$(UNDERSCORE_SHA) .make/include .make/vendor/underscore vendor/SPMediaKeyTap vendor/JSONKit Rackmate.app rackmate
test:
	@busted -m 'src/?.lua;include/?.lua' spec

$(OUTDIR)/%.o: %.m
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(CPPFLAGS) $< $(CFLAGS) -c -o $@
$(OUTDIR)/%.o: %.c
	$(CC) -MMD -MF $(@:.o=.d) -MT $@ $(CPPFLAGS) $< $(CFLAGS) -c -o $@

-include $(OBJS:.o=.d)


################################################################## directories
DIRS := $(sort $(dir $(OBJS))) .make/include .make/include/rackit Rackmate.app/Contents Rackmate.app/Contents/MacOS Rackmate.app/Contents/Resources
define mkdir
$(1):
	mkdir -p $(1)
endef
$(foreach o, $(OBJS), $(eval $(o): | $(dir $(o))))
$(foreach d, $(DIRS), $(eval $(call mkdir, $(d))))


####################################################################### vendor
include/underscore.lua: .make/$(UNDERSCORE_SHA)
.make/$(UNDERSCORE_SHA): vendor/underscore
	git --git-dir=$^/.git --work-tree=$^ reset --hard $(@F) > $@
vendor/underscore:
	git clone https://github.com/rackit/underscore.lua $@
vendor/SPMediaKeyTap:
	git clone https://github.com/rackit/SPMediaKeyTap $@
vendor/JSONKit:
	git clone https://github.com/johnezang/JSONKit vendor/JSONKit
