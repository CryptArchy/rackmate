#include <ctype.h>
#include <errno.h>
#include "lualib.h"
#include "lauxlib.h"
#include "rackmate.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef _WIN32
#include <pwd.h>
#include <unistd.h>
#else
#include <direct.h>
#include <shlobj.h>
#include <wchar.h>
#define mkdir(x, y) _mkdir(x)
#endif

#if __STRICT_ANSI__ && __GNUC__
#define strdup(x) strcpy(malloc(strlen(x) + 1), x)
#endif

#include "rackmate.lua.h"


//////////////////////////////////////////////////////////////////////// utils
static bool mkpath(const char *path) {
    char opath[4096]; //TODO use Lua so any length is okay! Or maybe C99 variable length arrays
    strncpy(opath, path, sizeof(opath));
    size_t len = strlen(opath);
    if (opath[len - 1] == '/')
        opath[len - 1] = '\0';
    for (char *p = opath; *p; p++)
        if (*p == '/') {
            *p = '\0';
            mkdir(opath, S_IRWXU); // ignore errors here, report for final
            *p = '/';              // mkdir only: easier code; works the same
        }
    return mkdir(opath, S_IRWXU) == 0;
}

#ifndef _WIN32
const char *homepath() {
    const char *d = getenv("HOME");
    if (d)
        return d;
    struct passwd *pwd = getpwuid(getuid());
    if (pwd)
       return pwd->pw_dir;
   return getenv("TMP") ?: "/tmp";
}

const char *syspath(int key) {
    switch (key) {
    #ifdef __APPLE__
        case 0:  return "Library/Caches/co.rackit.mate";
        case 1:  return "Library/Preferences/co.rackit.mate";
        default: return "Library/Application Support/Rackmate"; //yes, typically not reverse URL here
    #else
        case 0:  return ".cache/rackmate";
        case 1:  return ".config/rackmate";
        default: return ".local/rackmate";
    #endif
    }
}
#endif


//////////////////////////////////////////////////////////////////// lua utils
int lua_backtrace(lua_State *L) {
    size_t n;
    const char *s = lua_tolstring(L, 1, &n);

    // If we preface the error by OK it means it is a non-serious error that
    // doesn't need a backtrace, we use this when trying to read a closed
    // websocket connection, yeah don't use exceptions for flow-control, but…
    for (int x = 0, y = 0; x < n; ++x)
        if (s[x] == ':' && ++y == 3 && strncmp(s + x - 2, "OK", 2) == 0) {
            x++;
            fprintf(stderr, "%.*s\n", (int)n - x, s + x);
            return 0;
        }

    lua_getfield(L, LUA_GLOBALSINDEX, "debug");
    lua_getfield(L, -1, "traceback");
    lua_pushvalue(L, 1);    // pass error message
    lua_pushinteger(L, 2);  // skip this function and traceback
    lua_call(L, 2, 1);      // call debug.traceback
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    return 1;
}

#ifndef _WIN32
static int lua_xp_homedir(lua_State *L) {
    lua_pushstring(L, homepath());
    return 1;
}
#endif

static int lua_xp_mkpath(lua_State *L) {
    const char *path = lua_tostring(L, 1);
    struct stat s;
    int rv = stat(path, &s);
    if ((rv == -1 && errno == ENOENT && mkpath(path)) || (rv == 0 && s.st_mode & S_IFDIR && access(path, R_OK | X_OK | W_OK) == 0)) {
        lua_pushboolean(L, true);
        return 1;
    } else
        return luaL_error(L, "Failed to mkpath: %s: %s", path, strerror(errno));
}

static int lua_xp_sysdir(lua_State *L) {
#ifndef _WIN32
    lua_pushstring(L, homepath());
    lua_pushstring(L, "/");
    lua_pushstring(L, syspath(lua_tonumber(L, 1)));
    lua_concat(L, 3);
#else
    // we get the short path as it is always ASCII and Lua is no good with UTF16
    wchar_t longpath[MAX_PATH];
    SHGetFolderPathW(NULL, CSIDL_APPDATA, NULL, 0, longpath);
    wchar_t shortpath[1024];
    GetShortPathNameW(longpath, shortpath, sizeof(shortpath));
    size_t n = wcslen(shortpath);
    char ascii[n];
    for (int x = 0; x < n; ++x)
        ascii[x] = shortpath[x*2];
    lua_pushlstring(L, ascii, n);
#endif
    return 1;
}

#ifndef _WIN32
static int lua_xp_fork(lua_State *L) {
    lua_pushinteger(L, fork());
    return 1;
}

static int lua_xp__exit(lua_State *L) {
    _exit(lua_tonumber(L, 1));
    return 0; // never happens
}
#endif

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
#if !defined(NDEBUG) && !defined(_WIN32)
pthread_t lua_thread = NULL;
#endif

#ifdef RACKMATE_GUI
    int lua_thread_loop() {
#else
    SP_CALLCONV void spcb_logged_in(sp_session *session, sp_error err) {
        if (err != SP_ERROR_OK)
            fprintf(stderr, "Log in failed: %s\n", sp_error_message(err));
        else
            fprintf(stderr, "Logged in\n");
    }

    int main(int argc, char **argv) {
#endif
    #if !defined(NDEBUG) && !defined(_WIN32)
        lua_thread = pthread_self();
    #endif
    #ifndef RACKMATE_GUI
        if (argc > 2 && !strncmp(argv[1], "--user", 6)) {
            fprintf(stderr, "Password: ");
            char buf[128];
            sp_password = strdup(gets(buf));
            sp_username = strdup(argv[2]);
            //FIXME won't logout and in as new user if already logged in
        }
    #endif

        lua_State *L = lua_open();
        luaL_openlibs(L);

        luaL_register(L, LUA_STRLIBNAME, (luaL_reg[]){
            {"trim", lua_string_trim},
            {NULL,  NULL}
        });

        luaL_register(L, LUA_OSLIBNAME, (luaL_reg[]){
          #ifndef _WIN32
            { "homedir", lua_xp_homedir },
            { "fork", lua_xp_fork },
            { "_exit", lua_xp__exit },
          #endif
            { "mkpath", lua_xp_mkpath },
            { "sysdir", lua_xp_sysdir },
            {NULL,  NULL}
        });

        lua_getfield(L, LUA_GLOBALSINDEX, "package");
        lua_getfield(L, -1, "preload");
        lua_pushcfunction(L, luaopen_cjson);
        lua_setfield(L, -2, "cjson");

        luaopen_spotify(L);
        luaopen_websocket(L);

        lua_pushcfunction(L, lua_backtrace);

        int rv = luaL_loadbuffer(L, LUASRC, sizeof(LUASRC) - 1, "src");
        if (rv) {
            fprintf(stderr, "%s\n", lua_tostring(L, -1));
        } else {
            rv = lua_pcall(L, 0, 0, lua_gettop(L) - 1);
        }

    #ifdef RACKMATE_GUI
        lua_close(L);
    #endif
        return rv;
    }
