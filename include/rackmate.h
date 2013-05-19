#ifndef _RACKMATE_H_
#define _RACKMATE_H_

extern void tellmate(const char *what);
extern const char *homepath();
extern const char *syspath(int index);

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
