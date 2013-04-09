#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

int main(int argc, char **argv) {
    lua_State *L = lua_open();
    luaL_openlibs(L);
    int rv = luaL_dostring(L, "print(\"Hello world\")");
    lua_close(L);
    return rv;
}
