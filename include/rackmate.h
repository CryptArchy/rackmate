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
extern void spcb_logged_in(sp_session *session, sp_error err);
extern const char *syspath(int index);
extern void tellmate(const char *what);

#ifndef NDEBUG
#include <pthread.h>
extern pthread_t lua_thread;
#define is_lua_thread() (pthread_self() == lua_thread)
#else
#define is_lua_thread() (void)
#endif

#ifdef RACKMATE_GUI
extern int lua_thread_loop();
#endif

#endif



#ifdef __OBJC__

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@interface MBStatusItemView : NSView
@end

@interface MBWebSocketClient : NSObject
- (void)send:(NSString *)string;
@end

@interface MBInsomnia : NSObject
- (void)toggle:(BOOL)on;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

#endif
