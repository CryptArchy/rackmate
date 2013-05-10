#include "rackit/conf.h"
#include <arpa/inet.h>
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <netdb.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdlib.h>
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

static int lws_connect(lua_State* L) {
    int sockfd;
    struct addrinfo hints = {
        .ai_family = AF_INET,
        .ai_socktype = SOCK_STREAM
    }, *servinfo, *p;
    int rv = getaddrinfo(lua_tostring(L, 1), lua_tostring(L, 2), &hints, &servinfo);
    if (rv != 0)
        return luaL_error(L, "getaddrinfo: %s", strerror(errno));

    for(p = servinfo; p != NULL; p = p->ai_next) {
        if ((sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1) {
            perror("socket");
            continue;
        }
        if (connect(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
            close(sockfd);
            perror("connect");
            continue;
        }
        break;
    }
    lua_push_sock(L, sockfd);
    return 1;
}

static int lws_listen(lua_State *L) {
    listen(sockfd, 32 /*backlog queue size*/);
    return 0;
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
                lua_pushcfunction(L, lua_backtrace);
                lua_pushvalue(L, 1); // the callback
                lua_push_sock(L, newfd);
                lua_pushlstring(L, rsp, n);
                lua_pcall(L, 2, 0, lua_gettop(L) - 3);
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
    header[0] = 0x80 | (lua_tointeger(L, 2) ?: 1);
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
        n = 10;
    } else if (n > 125) {
        header[1] = 126;
        header[2] = (n >> 8) & 255;
        header[3] = n & 255;
        n = 4;
    } else {
        header[1] = n;
        n = 2;
    }
    if (lua_toboolean(L, 3))
        header[1] |= 0x80; // set masked bit

    lua_pushlstring(L, header, n);
    return 1;
}

static int lws_ntohll(lua_State *L) {
    const char *s = lua_tostring(L, 1);
    uint64_t v = *((uint64_t *)s);
    union { uint32_t lv[2]; uint64_t llv; } u;
    u.llv = v;
    uint64_t rv = ((uint64_t)ntohl(u.lv[0]) << 32) | (uint64_t)ntohl(u.lv[1]);
#ifdef RACKIT_LUA_INTEGER_IS_64BIT
    lua_pushinteger(L, rv);
#else
    lua_pushlstring(L, (char *)&v, 4);
#endif
    return 1;
}

static int lws_htonl(lua_State *L) {
    uint32_t *p = (uint32_t *)lua_tostring(L, 1);
    uint32_t i = ntohl(*p);
    lua_pushlstring(L, (const char *)&i, 4);
    return 1;
}

static int lws_sha1(lua_State *L) {
    size_t n;
    const char *rawinput = lua_tolstring(L, 1, &n);
#ifdef __APPLE__
    unsigned char input[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(rawinput, n, input);
#else
    #error need code for platform's sha1
#endif
    lua_pushlstring(L, (const char *)input, CC_SHA1_DIGEST_LENGTH);
    return 1;
}


static int lws_base64(lua_State *L) {
    static unsigned char base64EncodeLookup[65] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    size_t length;
    const char *inputBuffer = lua_tolstring(L, 1, &length);

    #define BINARY_UNIT_SIZE 3
    #define BASE64_UNIT_SIZE 4
    #define MAX_NUM_PADDING_CHARS 2
    #define OUTPUT_LINE_LENGTH 64
    #define INPUT_LINE_LENGTH ((OUTPUT_LINE_LENGTH / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE)
    #define CR_LF_SIZE 2

    size_t outputBufferSize =
            ((length / BINARY_UNIT_SIZE)
                + ((length % BINARY_UNIT_SIZE) ? 1 : 0))
                    * BASE64_UNIT_SIZE;
    outputBufferSize++; // Include space for a terminating zero

    char out[outputBufferSize];
    char *outputBuffer = out;
    size_t i = 0;
    size_t j = 0;
    size_t lineEnd = length;

    while (true) {
        if (lineEnd > length)
            lineEnd = length;

        for (; i + BINARY_UNIT_SIZE - 1 < lineEnd; i += BINARY_UNIT_SIZE) {
            // turn 48 bytes into 64 base64 characters
            outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
            outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
                | ((inputBuffer[i + 1] & 0xF0) >> 4)];
            outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i + 1] & 0x0F) << 2)
                | ((inputBuffer[i + 2] & 0xC0) >> 6)];
            outputBuffer[j++] = base64EncodeLookup[inputBuffer[i + 2] & 0x3F];
        }

        if (lineEnd == length)
            break;

        outputBuffer[j++] = '\r';
        outputBuffer[j++] = '\n';
        lineEnd += length;
    }

    if (i + 1 < length) { // the single '=' case
        outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
        outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
            | ((inputBuffer[i + 1] & 0xF0) >> 4)];
        outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i + 1] & 0x0F) << 2];
        outputBuffer[j++] = '=';
    } else if (i < length) { // the double '=' case
        outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
        outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0x03) << 4];
        outputBuffer[j++] = '=';
        outputBuffer[j++] = '=';
    }

    lua_pushlstring(L, out, j);
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

static inline int lws_mask(lua_State *L) {
    const uint32_t mask = rand();
    size_t N;
    const char *input = lua_tolstring(L, 1, &N);
    char out[N + 4];
    out[0] = (char)((mask >> 24) & 0xFF);
    out[1] = (char)((mask >> 16) & 0xFF);
    out[2] = (char)((mask >> 8) & 0XFF);
    out[3] = (char)((mask & 0XFF));
    for (int i = 0; i < N; ++i)
        out[i + 4] = input[i] ^ out[i % 4];
    lua_pushlstring(L, out, N + 4);
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
    int rn = 0;
    if (lua_isnil(L, 2))
        n = 2048;
    char buf[n];
    char *p = buf;
    while(rn < n) {
        int rv = recv(sockfd, p, n, 0);
        if (rv == 0) {
            lws_sock_close(L);
            break;
        } else if (rv == -1)
            return luaL_error(L, "recv: %s", strerror(errno));
        rn += rv;
        p += rv;
        if (lua_isnil(L, 2))
            break;
    }
    lua_pushlstring(L, buf, rn);
    return 1;
}

static int lws_sock_write(lua_State *L) {
    #ifdef __APPLE__
    #define MSG_NOSIGNAL 0
    #endif

    int fd = lua_tosockfd(L, 1);

    size_t n;
    const char *payload = lua_tolstring(L, 2, &n);
    int rv = send(fd, payload, n, MSG_NOSIGNAL);
    if (rv == -1) luaL_error(L, "send: %d: %s: %s\n", fd, strerror(errno), payload);
    if (rv != n) fprintf(stderr, "Didn't send() all :(\n");
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
        {"connect", lws_connect},
        {"ntohs", lws_ntohs},
        {"ntohll", lws_ntohll},
        {"htonl", lws_htonl},
        {"mask", lws_mask},
        {"unmask", lws_unmask},
        {"base64", lws_base64},
        {"sha1", lws_sha1},
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
