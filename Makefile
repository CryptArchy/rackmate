ifneq "$(wildcard keys.c)" "keys.c"
  $(error You must create keys.c: see README)
endif

.PHONY: dist-clean clean test
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
	rm -rf $(DIRS) $(OBJS) $(DEPS)
dist-clean:
	rm -rf $(filter-out .make/conf.c, $(wildcard .make/*)) vendor/underscore
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

.make/$(UNDERSCORE_SHA): vendor/underscore
	git --git-dir=$^/.git --work-tree=$^ reset --hard $(@F) > $@
vendor/underscore:
	git clone https://github.com/rackit/underscore.lua $@

-include $(DEPS)

######################################################################## notes
# * GNU Make sets CC itself if none is set here OR the environment
# * We get cc to generate the header-deps for each .c file and then include
#   that file into this Makefile as it is a makefile-list-of-rules itself
# * The minus in front of the include prevents that rule printing a warning
#   if the DEPS files don't exist, which they won't on the first run.
