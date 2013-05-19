#ifndef RACKMATE_EXTLIB_H
#define RACKMATE_EXTLIB_H

extern void tellmate(const char *what);

#ifndef NDEBUG
#include <pthread.h>
extern pthread_t lua_thread;
#define is_lua_thread() (pthread_self() == lua_thread)
#else
#define is_lua_thread() (void)
#endif

#endif
