SRC = $(shell find c -name \*.c)
OBJ = $(SRC:.c=.o)

%.o: %.c
	$(CC) $(CFLAGS) -Iinclude -c $^ -o $@

rackmate: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ -llua $^

.PHONY: clean
clean:
	rm -f $(OBJ) rackmate

# NOTES
# * GNU Make sets CC itself if none is set here OR the environment
