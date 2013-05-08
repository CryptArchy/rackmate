#include "rackit/conf.h"
#include <arpa/inet.h>
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <netinet/in.h>
#include <stdbool.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>

int sockfd;
int lua_backtrace(lua_State *L);


static void lua_push_clients(lua_State *L) {
    lua_getglobal(L, "require");
    lua_pushliteral(L, "websocket");
    lua_call(L, 1, 1);
    lua_pushstring(L, "clients");
    lua_gettable(L, -2);
    lua_remove(L, -2);
    luaL_checktype(L, -1, LUA_TTABLE);
}

static int lws_bind(lua_State *L) {
    sockfd = socket(PF_INET, SOCK_STREAM, 0);

    // lose the pesky "Address already in use" error message
    int yes = 1;
    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1) {
        lua_pushliteral(L, "setsockopt");
        return lua_error(L);
    }
    #ifdef __APPLE__
    // prevent SIGPIPE, other platforms support MSG_NOSIGNAL in send() flags
    setsockopt(sockfd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(int));
    #endif

    struct sockaddr_in serv_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(13581),
        .sin_addr = { .s_addr = inet_addr("127.0.0.1") }
    };

    if (bind(sockfd, (struct sockaddr *)&serv_addr, sizeof serv_addr) == -1) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }

    return 0;
}

static int lws_listen(lua_State *L) {
    listen(sockfd, 32 /*backlog queue size*/);
    return 0;
}

static void lua_push_sock(lua_State *L, int fd) {
    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "__index");
    luaL_getmetatable(L, "WebSocketClient");
    lua_settable(L, -3);
    lua_setmetatable(L, -2);
    lua_pushliteral(L, "sockfd");
    lua_pushinteger(L, fd);
    lua_settable(L, -3);
}

static int lws_select(lua_State *L) {
    int maxfd = sockfd;
    fd_set fdset;
    FD_ZERO(&fdset);
    FD_SET(sockfd, &fdset);
    int fds[256]; fds[0] = sockfd;
    int nfds = 1;

    // iterate over Lua `clients` and assemble fdset and maxfd for select
    lua_push_clients(L);
    lua_pushnil(L);
    while (lua_next(L, -2)) {
        lua_pushvalue(L, -2);
        const int fd = lua_tointeger(L, -1);
        if (fd > maxfd) maxfd = fd;
        fds[nfds++] = fd;
        FD_SET(fd, &fdset);
        lua_pop(L, 2); // pop key & key copy
    }
    lua_pop(L, 1);

    int rv = select(maxfd + 1, &fdset, NULL, NULL, NULL);

    if (rv == -1) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }
    int maxfdcp = maxfd;
    for (int ii = 0; ii < nfds; ++ii) {
        int fd = fds[ii];
        if (!FD_ISSET(fd, &fdset))
            continue;
        if (fd == sockfd) {
            struct sockaddr_storage client;
            socklen_t sz = sizeof client;

            // prevent race condition: http://stackoverflow.com/questions/3444729
            //int flags = fcntl(sockfd, F_GETFL, 0);
            //fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);
            int newfd = accept(sockfd, (struct sockaddr *) &client, &sz);
            //fcntl(sockfd, F_SETFL, flags);

            if (newfd == -1) {
                perror("accept");
                continue;
            }
            char rsp[2048];
            int n = recv(newfd, rsp, sizeof rsp, 0);
            if (n <= 0) {
                perror("recv");
                close(newfd);
                continue;
            }
            if (strncmp(rsp, "ctc:", 4) == 0) {
                rsp[n] = '\0';
                char *p = rsp + 4;
                char *dot = strchr(p, '.');
                *dot = '\0';
                lua_getglobal(L, "require");
                lua_pushstring(L, p);
                lua_call(L, 1, 1);
                lua_pushstring(L, dot + 1);
                lua_gettable(L, -2);
                lua_call(L, 0, 0);
                lua_pop(L, 1); // pop require'd table
            } else {
                lua_pushvalue(L, 1); // the callback
                lua_push_sock(L, newfd);
                lua_pushlstring(L, rsp, n);
                lua_call(L, 2, 0);
            }
        } else {
            lua_pushcfunction(L, lua_backtrace);
            lua_pushvalue(L, 2); // the callback
            lua_push_sock(L, fd);
            lua_pcall(L, 1, 0, lua_gettop(L) - 2);
        }
    }
    return 0;
}

static int lws_ntohs(lua_State *L) {
    uint16_t *p = (uint16_t *)lua_tostring(L, 1);
    lua_pushinteger(L, ntohs(*p));
    return 1;
}

static int lws_frame_header(lua_State *L) {
    uint64_t n = lua_tointeger(L, 1);
    char header[10];
    header[0] = 0x81;
    if (n > 65535) {
        header[1] = 127;
        header[2] = (n >> 56) & 255;
        header[3] = (n >> 48) & 255;
        header[4] = (n >> 40) & 255;
        header[5] = (n >> 32) & 255;
        header[6] = (n >> 24) & 255;
        header[7] = (n >> 16) & 255;
        header[8] = (n >>  8) & 255;
        header[9] = n & 255;
        lua_pushlstring(L, header, 10);
    } else if (n > 125) {
        header[1] = 126;
        header[2] = (n >> 8) & 255;
        header[3] = n & 255;
        lua_pushlstring(L, header, 4);
    } else {
        header[1] = n;
        lua_pushlstring(L, header, 2);
    }
    return 1;
}

static int lws_ntohll(lua_State *L) {
    const char *s = lua_tostring(L, 1);
    unsigned long long v = *((unsigned long long *)s);
    union { unsigned long lv[2]; unsigned long long llv; } u;
    u.llv = v;
    uint64_t rv = ((unsigned long long)ntohl(u.lv[0]) << 32) | (unsigned long long)ntohl(u.lv[1]);
#ifdef RACKIT_LUA_INTEGER_IS_64BIT
    lua_pushinteger(L, rv);
#else
    lua_pushlstring(L, (char *)&v, 4);
#endif
    return 1;
}

static int lws_sha1base64(lua_State *L) {
    size_t n;
    const char *rawinput = lua_tolstring(L, 1, &n);
#ifdef __APPLE__
    unsigned char input[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(rawinput, n, input);
#else
    #error need code for platform's sha1
#endif

//////
    static const char map[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    char data[28];
    uint8_t *out = (uint8_t *)data;
    for (int i = 0; i < 20;) {
        int v  = 0;
        for (const int N = i + 3; i < N; i++) {
            v <<= 8;
            v |= 0xFF & input[i];
        }
        *out++ = map[v >> 18 & 0x3F];
        *out++ = map[v >> 12 & 0x3F];
        *out++ = map[v >> 6 & 0x3F];
        *out++ = map[v >> 0 & 0x3F];
    }
    out[-2] = map[(input[19] & 0x0F) << 2];
    out[-1] = '=';

    lua_pushlstring(L, data, sizeof(data));

    return 1;
}

static inline int lws_unmask(lua_State *L) {
    size_t n;
    const char *masked = lua_tolstring(L, 1, &n);
    char unmasked[n - 4]; // skip first 4 bytes, is header
    for (int x = 4; x < n; ++x) {
        char c = masked[x] ^ masked[x%4];
        unmasked[x - 4] = c;
    }
    lua_pushlstring(L, unmasked, n - 4);
    return 1;
}

static inline int lua_tosockfd(lua_State *L, int index) {
    lua_pushliteral(L, "sockfd");
    if (index < 0) index--;
    lua_gettable(L, index);
    int rv = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return rv;
}

static int lws_sock_close(lua_State *L) {
    int fd = lua_tosockfd(L, 1);
    close(fd);
    lua_push_clients(L);
    lua_pushinteger(L, fd);
    lua_pushnil(L);
    lua_settable(L, -3);
    lua_pop(L, 1);
    return 0;
}

static int lws_sock_read(lua_State *L) {
    int sockfd = lua_tosockfd(L, 1);
    uint64_t n
#ifdef RACKIT_LUA_INTEGER_IS_64BIT
     = lua_tointeger(L, 2);
#else
    ;
    if (lua_isnumber(L, 2)) {
        n = lua_tointeger(L, 2)
    } else {
        #error TODO
    }
#endif
    char buf[n];
    int rn = recv(sockfd, buf, n, 0);
    if (rn == 0) {
        lws_sock_close(L);
        return 0;
    } else if (rn == -1) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    } else if (rn != n) {
        lua_pushliteral(L, "Didn't receive all data :(");
        return lua_error(L);
    } else
        lua_pushlstring(L, buf, n);
    return 1;
}

static int lws_sock_write(lua_State *L) {
    #ifdef __APPLE__
    #define MSG_NOSIGNAL 0
    #endif

    size_t n;
    const char *payload = lua_tolstring(L, -1, &n);
    send(lua_tosockfd(L, -2), payload, n, MSG_NOSIGNAL);
    return 0;
}

static int lws_sock_read_header(lua_State *L) {
    char bytes[2];
    int sockfd = lua_tosockfd(L, 1);
    int rv = recv(sockfd, bytes, 2, 0);

    if (rv == 0) { // socket was closed clientside
        lws_sock_close(L);
        return 0;
    } else if (rv == -1) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }

    uint16_t const N = bytes[1] & 0x7f;
    char const opcode = bytes[0] & 0x0f;

    // TODO support fragmented frames (first bit unset in control frame)
    if (!bytes[0] & 0x80) {
        lua_pushliteral(L, "Can't decode fragmented frames!");
        return lua_error(L);
    }
    if (!bytes[1] & 0x80) {
        lua_pushliteral(L, "Can only handle websocket frames with masks!");
        return lua_error(L);
    }
    lua_pushinteger(L, opcode);
    lua_pushinteger(L, N);
    return 2;
}

int luaopen_websocket(lua_State *L) {
    luaL_register(L, "websocket.c", (struct luaL_reg[]){
        {"bind", lws_bind},
        {"listen", lws_listen},
        {"select", lws_select},
        {"ntohs", lws_ntohs},
        {"ntohll", lws_ntohll},
        {"unmask", lws_unmask},
        {"sha1base64", lws_sha1base64},
        {"frame_header", lws_frame_header},
        {NULL, NULL}
    });

    luaL_newmetatable(L, "WebSocketClient");
    lua_pushliteral(L, "close");
    lua_pushcfunction(L, lws_sock_close);
    lua_rawset(L, -3);
    lua_pushliteral(L, "read_header");
    lua_pushcfunction(L, lws_sock_read_header);
    lua_rawset(L, -3);
    lua_pushliteral(L, "read");
    lua_pushcfunction(L, lws_sock_read);
    lua_rawset(L, -3);
    lua_pushliteral(L, "write");
    lua_pushcfunction(L, lws_sock_write);
    lua_rawset(L, -3);
    lua_pop(L, 1);

    return 1;
}
