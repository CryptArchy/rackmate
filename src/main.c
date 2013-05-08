#include <ctype.h>
#include <errno.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef _WIN32
#include <pwd.h>
#include <unistd.h>
#endif

int luaopen_spotify(lua_State *L);
int luaopen_websocket(lua_State *L);
int luaopen_cjson(lua_State *L);

pthread_t rackit_lua_thread;


//////////////////////////////////////////////////////////////////////// utils
static bool mkpath(const char *path) {
    char opath[4096];
    strncpy(opath, path, sizeof(opath));
    size_t len = strlen(opath);
    if (opath[len - 1] == '/')
        opath[len - 1] = '\0';
    for (char *p = opath; *p; p++)
        if (*p == '/') {
            *p = '\0';
            if (!mkdir(opath, S_IRWXU))
                return false;
            *p = '/';
        }
    return mkdir(opath, S_IRWXU);
}

static const char *homepath() {
#ifdef _WIN32
    #error unimplemented
#else
    const char *d = getenv("HOME");
    if (d)
        return d;
    struct passwd *pwd = getpwuid(getuid());
    if (pwd)
       return pwd->pw_dir;
   return getenv("TMP") ?: "/tmp";
#endif
}

static const char *syspath(int key) {
    switch (key) {
    #ifdef __APPLE__
        case 0:  return "Library/Caches/Rackmate";
        case 1:  return "Library/Preferences/Rackmate";
        default: return "Library/Application Support/Rackmate";
    #elif _WIN32
    #error unimplemented
    #else
        case 0:  return ".cache/rackmate";
        case 1:  return ".config/rackmate";
        default: return ".local/rackmate";
    #endif
    }
}


//////////////////////////////////////////////////////////////////// lua utils
int lua_backtrace(lua_State *L) {
    lua_getfield(L, LUA_GLOBALSINDEX, "debug");
    lua_getfield(L, -1, "traceback");
    lua_pushvalue(L, 1);    // pass error message
    lua_pushinteger(L, 2);  // skip this function and traceback
    lua_call(L, 2, 1);      // call debug.traceback
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    return 1;
}

static int lua_xp_homedir(lua_State *L) {
    lua_pushstring(L, homepath());
    return 1;
}

static int lua_xp_mkpath(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (!mkpath(path))
        luaL_error(L, "Failed to mkpath: %s: %s", path, strerror(errno));
    return 0;
}

static int lua_xp_access(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    lua_pushboolean(L, access(path, R_OK | W_OK));
    return 1;
}

static int lua_xp_sysdir(lua_State *L) {
    lua_pushstring(L, syspath(lua_tonumber(L, 1)));
    return 1;
}

static int lua_xp_fork(lua_State *L) {
    lua_pushinteger(L, fork());
    return 1;
}

static int lua_xp__exit(lua_State *L) {
    _exit(lua_tonumber(L, 1));
    return 0; // never happens
}

static int lua_string_trim(lua_State *L) {
    size_t size;
    const char *front = luaL_checklstring(L, 1, &size);
    const char *end = &front[size - 1];
    for (; size && isspace(*front); size--, front++);
    for (; size && isspace(*end); size--, end--);
    lua_pushlstring(L, front, (size_t)(end - front) + 1);
    return 1;
}


///////////////////////////////////////////////////////////////////////// main
#ifdef RACKIT_GUI
    #ifdef __APPLE__
        int NSApplicationMain(int, const char**);

        int main(int argc, const char **argv) {
            return NSApplicationMain(argc, argv);
        }
    #endif

    int lua_thread_loop(const char *MAIN_LUA_PATH) {
#else
    #define MAIN_LUA_PATH "src/main.lua"

    int main(int argc, char **argv) {
#endif
        rackit_lua_thread = pthread_self();

        lua_State *L = lua_open();
        luaL_openlibs(L);

        luaL_register(L, LUA_STRLIBNAME, (luaL_reg[]){
            {"trim", lua_string_trim},
            {NULL,  NULL}
        });

        luaL_register(L, LUA_OSLIBNAME, (luaL_reg[]){
            { "homedir", lua_xp_homedir },
            { "mkpath", lua_xp_mkpath },
            { "access", lua_xp_access },
            { "sysdir", lua_xp_sysdir },
            { "fork", lua_xp_fork },
            { "_exit", lua_xp__exit },
            {NULL,  NULL}
        });

        lua_getfield(L, LUA_GLOBALSINDEX, "package");
        lua_getfield(L, -1, "preload");
        lua_pushcfunction(L, luaopen_cjson);
        lua_setfield(L, -2, "cjson");

        luaopen_spotify(L);
        luaopen_websocket(L);

        lua_pushcfunction(L, lua_backtrace);

        int rv = luaL_loadfile(L, MAIN_LUA_PATH);
        if (rv) {
            fprintf(stderr, "%s\n", lua_tostring(L, -1));
        } else {
            rv = lua_pcall(L, 0, 0, lua_gettop(L) - 1);
        }

    #ifdef RACKIT_GUI
        lua_close(L);
    #endif
        return rv;
    }
