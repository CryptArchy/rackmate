#ifndef _RACKMATE_H_
#define _RACKMATE_H_

#include "lua.h"
#include "spotify.h"

extern char *sp_username;
extern char *sp_password;
extern sp_session *session;

extern size_t base64_size(size_t length);
extern size_t base64(const char *inputBuffer, size_t inputBufferSize, char *outputBuffer, size_t outputBufferSize);
extern const char *homepath();
extern int lua_backtrace(lua_State *L);
extern int luaopen_spotify(lua_State *L);
extern int luaopen_websocket(lua_State *L);
extern int luaopen_cjson(lua_State *L);
SP_CALLCONV extern void spcb_logged_in(sp_session *session, sp_error err);
extern const char *syspath(int index);
extern void tellmate(const char *what);

#if !defined(NDEBUG) && !defined(_WIN32)
#include <pthread.h>
extern pthread_t lua_thread;
#define is_lua_thread() (pthread_self() == lua_thread)
#else
#define is_lua_thread() 1
#endif

#ifdef _WIN32
// returns wide strings on Windows, the type is `char *` on all platforms
// so the code is not an ifdef mess. The value at index is REPLACED with
// the 16 bit unicode wide string version, so keep a copy if you need the
// utf8 version.
extern const wchar_t *lua_topath(lua_State *L, int idx);
#else
#define lua_topath lua_tostring
#endif

#ifdef RACKMATE_GUI
extern int lua_thread_loop();
#endif

#endif



#ifdef __OBJC__

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@class AsyncSocket;

@interface MBStatusItemView : NSView {
    NSTextField *user;
    NSTextField *pass;
    NSButton *login;
    NSWindow *window;
}
@end

@interface MBWebSocketClient : NSObject {
    AsyncSocket *socket;
}
- (void)send:(NSString *)string;
@end

typedef uint32_t IOPMAssertionID;

@interface MBInsomnia : NSObject {
    IOPMAssertionID assertionID;
}
- (void)toggle:(BOOL)on;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSStatusItem *statusItem;
    NSMenu *menu;
    NSMenuItem *artistMenuItem;
    NSMenuItem *trackMenuItem;
    NSMenuItem *spotifyStatusMenuItem;
    NSMenuItem *separator;
    NSMenuItem *pauseMenuItem;
    NSThread *thread;

    MBInsomnia *insomnia;
    MBWebSocketClient *ws;

    BOOL notNow;
    BOOL waitingToQuit;
    BOOL updateWaiting;
    BOOL extracting;
}
@end

#endif
