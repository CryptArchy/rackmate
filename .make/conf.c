#include "luaconf.h"
#include <stdio.h>

int main(int argc, char ** argv) {
    if (sizeof(LUA_INTEGER) == 8)
        printf("#define RACKIT_LUA_INTEGER_IS_64BIT 1\n");
    return 0;
}
