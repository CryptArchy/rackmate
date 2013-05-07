#include "../keys.c"
#include "extlib.h"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <pthread.h>
#include <signal.h>
#include "spotify.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>


#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
static void tellmate(const char *what) {
    struct sockaddr_in serv_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(13581),
        .sin_addr = { .s_addr = inet_addr("127.0.0.1") }
    };
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    int rv = connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr));
    if (rv == -1)
        return perror("ctc connect");
    if (write(sockfd, what, strlen(what)) == -1)
        perror("write");
    else
        close(sockfd);
}


#define HERR(fn) {sp_error sperr = (fn); if (sperr) fprintf(stderr, "%s\n", sp_error_message(sperr)); }

static sp_session *session = NULL;
static sp_track *loaded_track = NULL;
static sp_track *prefetched_track = NULL;
static audio_fifo_t *fifo;
static int duration; // in frames
static int position; // strictly, decoded position in frames
static bool asked_for_next_track = false;
static bool waiting_for_metadata = false;

static int callback_next = 0;
static int callback_ontrack = 0;
static int callback_onexhaust = 0;
static lua_State *process_events_L;


static void log(sp_session *session, const char *message) {
    fputs(message, stderr);
}

static void ffs_go() {
    if (!fifo) {
        fifo = malloc(sizeof(audio_fifo_t));
        audio_init(fifo);
    }
    asked_for_next_track = false;
    position = 0;
    duration = sp_track_duration(loaded_track) * 44100 / 1000;
    sp_session_player_load(session, loaded_track);
    sp_session_player_play(session, true);
}

static void metadata_updated(sp_session *session) {
    if (waiting_for_metadata) {
        ffs_go();
        waiting_for_metadata = false;
    }
}

static int music_delivery(sp_session *sess, const sp_audioformat *format, const void *frames, int num_frames) {
    if (num_frames == 0)
        return 0; // Audio discontinuity, do nothing

    //TODO use a ringbuffer FFS
    pthread_mutex_lock(&fifo->mutex);

    /* Buffer one second of audio */
    if (fifo->qlen > format->sample_rate) {
        pthread_mutex_unlock(&fifo->mutex);
        return 0;
    }

    size_t sz = num_frames * sizeof(int16_t) * format->channels;

    audio_fifo_data_t *afd = malloc(sizeof(audio_fifo_data_t) + sz);
    memcpy(afd->samples, frames, sz);

    afd->nsamples = num_frames;
    afd->rate = format->sample_rate;
    afd->channels = format->channels;

    TAILQ_INSERT_TAIL(&fifo->q, afd, link);
    fifo->qlen += num_frames;

    pthread_cond_signal(&fifo->cond);
    pthread_mutex_unlock(&fifo->mutex);

    position += num_frames;
    if (!asked_for_next_track && position > duration - 20 * 44100) {
        asked_for_next_track = true;
        tellmate("ctc:spotify.spool");
    }

    return num_frames;
}

static void sp_error_occurred(sp_session *session, sp_error error) {
    HERR(error);
}

static void notify_main_thread(sp_session *session) {
    #ifdef __APPLE__
    // for some reason this gets called on the main thread during login
    // this breaks our start up sequence as the ctc socket is not yet listening
    if (pthread_main_np()) {
        int t;
        sp_session_process_events(session, &t);
        return;
    }
    #endif
    tellmate("ctc:spotify.process_events");
}

static void end_of_track(sp_session *session) {
    sp_track_release(loaded_track);
    if (prefetched_track) {
        loaded_track = prefetched_track;
        if (sp_track_error(loaded_track) == SP_ERROR_OK) {
            ffs_go();
        } else
            waiting_for_metadata = true;
    } else {
        fprintf(stderr, "No prefetched track");
        loaded_track = NULL;
    }
}


sp_session_callbacks session_callbacks = {
    .notify_main_thread = notify_main_thread,

    .logged_out = NULL,
    .play_token_lost = NULL,

    .metadata_updated = &metadata_updated,
    .start_playback = NULL,
    .get_audio_buffer_stats = NULL,
    .music_delivery = &music_delivery,
    .stop_playback = NULL,
    .end_of_track = &end_of_track,

    .message_to_user = &log,
    .log_message = &log,

    .streaming_error = &sp_error_occurred,
    .offline_error = &sp_error_occurred,
    .scrobble_error = &sp_error_occurred,
    .connection_error = &sp_error_occurred,
    .logged_in = &sp_error_occurred
};


static void logout() {
    fprintf(stderr, "logout\n");
    sp_session_logout(session);
    sp_session_release(session);
    session = NULL;
}

static void signaled(int sig) {
    signal(sig, SIG_DFL);
    logout();
    kill(getpid(), SIGINT);
}

static void search_complete(sp_search *search, void *userdata) {
    lua_State *L = process_events_L;
    const int R = (int)userdata;

    lua_rawgeti(L, LUA_REGISTRYINDEX, R);
    lua_newtable(L);
    for (int x = 0, n = sp_search_num_tracks(search); x < n; ++x) {
        sp_track *track = sp_search_track(search, x);

        sp_link *link = sp_link_create_from_track(track, 0);
        char url[256];
        sp_link_as_string(link, url, sizeof(url));
        sp_link_release(link);

        lua_pushinteger(L, x + 1);
        lua_newtable(L);
        lua_pushliteral(L, "title");
        lua_pushstring(L, sp_track_name(track));
        lua_settable(L, -3);
        lua_pushliteral(L, "url");
        lua_pushstring(L, url);
        lua_settable(L, -3);
        lua_settable(L, -3);
    }
    lua_call(L, 1, 0);

    luaL_unref(L, LUA_REGISTRYINDEX, R);
    sp_search_release(search);
}

static int lua_spotify_search(lua_State *L) {
    lua_pushvalue(L, 2);
    sp_search_create(session,
                     luaL_checkstring(L, 1),
                     0, 200, 0, 0, 0, 0, 0, 0, SP_SEARCH_STANDARD,
                     &search_complete,
                     (void *)luaL_ref(L, LUA_REGISTRYINDEX));
    return 0;
}

static int lua_spotify_process_events(lua_State *L) {
    process_events_L = L;
    int timeout = 0;
    sp_session_process_events(session, &timeout);
    return 0;
}

static int lua_spotify_play(lua_State *L) {
    #define foo(token) \
        if (callback_ ## token) luaL_unref(L, LUA_REGISTRYINDEX, callback_ ## token); \
        lua_pushliteral(L, #token); \
        lua_gettable(L, -1); \
        callback_ ## token = luaL_ref(L, LUA_REGISTRYINDEX)
    foo(next);
    foo(ontrack);
    foo(onexhaust);
    #undef foo

    sp_link *link = sp_link_create_from_string(luaL_checkstring(L, 1));
    sp_track_add_ref(loaded_track = sp_link_as_track(link));
    sp_link_release(link);
    if (sp_track_error(loaded_track) == SP_ERROR_OK) {
        ffs_go();
    } else
        waiting_for_metadata = true;
    return 0;
}

static int lua_spotify_prefetch(lua_State *L) {
    const char *url = lua_tostring(L, 1);
    if (!url) return 0;
    sp_link *link = sp_link_create_from_string(url);
    sp_track_add_ref(prefetched_track = sp_link_as_track(link));
    sp_link_release(link);
    HERR(sp_session_player_prefetch(session, prefetched_track));
    return 0;
}

// used to get the next track for play, called from the main thread so that
// Lua doesn’t segfault. Thus it being a public function and using tellmate()
static int lua_spotify_spool(lua_State *L) {
    fprintf(stderr, "spool\n");
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback_next);
    lua_call(L, 0, 1);
    lua_spotify_prefetch(L);
    return 0;
}

static int lua_spotify_login(lua_State *L) {
    lua_getglobal(L, "os");
    lua_pushliteral(L, "dir");
    lua_gettable(L, -2);
    lua_pushliteral(L, "prefs");
    lua_gettable(L, -2);
    lua_pushliteral(L, "Spotify");
    lua_call(L, 1, 1);
    const char *prefs = lua_tostring(L, -1);
    lua_pop(L, 1);
    lua_pushliteral(L, "cache");
    lua_gettable(L, -2);
    lua_pushliteral(L, "Spotify");
    lua_call(L, 1, 1);
    const char *cache = lua_tostring(L, -1);
    lua_pop(L, 3);

    sp_session_config spconfig = {
        .api_version = SPOTIFY_API_VERSION,
        .cache_location = cache,
        .settings_location = prefs,
        .application_key_size = g_appkey_size,
        .application_key = g_appkey,
        .user_agent = "Rackmate",
        .callbacks = &session_callbacks,
        .initially_unload_playlists = false, // don't waste RAM
        NULL
    };

    HERR(sp_session_create(&spconfig, &session));
    sp_session_set_connection_rules(session, SP_CONNECTION_RULE_NETWORK); // prevent offline sync
    sp_session_login(session, RACKMATE_USERNAME, RACKMATE_PASSWORD, false, NULL);

    atexit(&logout);
    signal(SIGINT, signaled);

    return 0;
}

int luaopen_spotify(lua_State *L) {
    luaL_register(L, "spotify", (struct luaL_reg[]){
        {"login", lua_spotify_login},
        {"search", lua_spotify_search},
        {"process_events", lua_spotify_process_events},
        {"play", lua_spotify_play},
        {"prefetch", lua_spotify_prefetch},
        {"spool", lua_spotify_spool},
        {NULL, NULL},
    });

    return 1;
}
