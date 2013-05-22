#include "../keys.c"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <OpenAL/al.h>
#include <OpenAL/alc.h>
#include "rackmate.h"
#include <signal.h>
#include "spotify.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

static int lua_spotify_stop(lua_State *L);

#define E_LUA_PCALL(p1, p2, p3) \
    if (lua_pcall(p1, p2, p3, 0) != 0) { \
        fprintf(stderr, "%s\n", lua_tostring(p1, -1)); \
        lua_pop(p1, 1); \
    }

#define AL_NUM_BUFFERS 44    // Spotify gives us 2048 frames per callback, so
ALCdevice *al_device = NULL; // this gives us ~2s audio at a 44100 sample rate
ALuint al_source;
ALuint al_buffers[AL_NUM_BUFFERS];
ALCcontext *al_context;

char *sp_username = NULL;
char *sp_password = NULL;

#define HERR(fn) {sp_error sperr = (fn); if (sperr) fprintf(stderr, "%s\n", sp_error_message(sperr)); }

sp_session *session = NULL;
static sp_track *loaded_track = NULL;
static sp_track *prefetched_track = NULL;
static int duration; // in frames
static int position; // strictly, decoded position in frames
static bool asked_for_next_track = false;
static bool waiting_for_metadata = false;
static lua_State *process_events_L;
static int callback_next = 0;
static int callback_ontrack = 0;
static int callback_onexhaust = 0;
static int callback_usability_status_change = 0;



static void ffs_go(lua_State *L) {                    assert(is_lua_thread());
    if (!al_device) {
        al_device = alcOpenDevice(NULL);
        al_context = alcCreateContext(al_device, NULL);
        alcMakeContextCurrent(al_context);
        alListenerf(AL_GAIN, 1.0f);
        alDistanceModel(AL_NONE);
        alGenBuffers(AL_NUM_BUFFERS, al_buffers);
        alGenSources(1, &al_source);
    }

    asked_for_next_track = false;
    position = 0;
    duration = sp_track_duration(loaded_track) * 44100 / 1000;
    sp_session_player_load(session, loaded_track);
    sp_session_player_play(session, true);

    sp_link *link = sp_link_create_from_track(loaded_track, 0);
    char url[256];
    int n = sp_link_as_string(link, url, sizeof(url));
    sp_link_release(link);
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ontrack);
    lua_pushlstring(L, url, n);
    E_LUA_PCALL(L, 1, 0);
}

SP_CALLCONV static void metadata_updated(sp_session *session) {   assert(is_lua_thread());
    if (waiting_for_metadata && sp_track_error(loaded_track) == SP_ERROR_OK) {
        ffs_go(process_events_L);
        waiting_for_metadata = false;
    }
}

SP_CALLCONV static int music_delivery(sp_session *sess, const sp_audioformat *format, const void *frames, int num_frames) {
    assert(!is_lua_thread());

    if (num_frames == 0)
        return 0; // Audio discontinuity, do nothing

    ALint value;
    alGetSourcei(al_source, AL_BUFFERS_QUEUED, &value);
    if (value == AL_NUM_BUFFERS) {
        alGetSourcei(al_source, AL_SOURCE_STATE, &value);
        if (value == AL_STOPPED || value == AL_INITIAL)
            alSourcePlay(al_source);
        alGetSourcei(al_source, AL_BUFFERS_PROCESSED, &value);
        if (value) {
            ALuint buffer;
            alSourceUnqueueBuffers(al_source, 1, &buffer);
            alBufferData(buffer,
                     format->channels == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16,
                     frames,
                     num_frames * sizeof(int16_t) * format->channels,
                     format->sample_rate);
            alSourceQueueBuffers(al_source, 1, &buffer);
        } else
            return 0; // try again later thanks
    } else {
        alBufferData(al_buffers[value],
                     AL_FORMAT_STEREO16,
                     frames,
                     num_frames * sizeof(int16_t) * format->channels,
                     format->sample_rate);
        alSourceQueueBuffers(al_source, 1, &al_buffers[value]);
    }

    // TODO position should be done at the OUTPUT portion dumbo
    // NOTE though the fetch should be done before all decoding has been seeded
    position += num_frames;
    if (!asked_for_next_track && position > duration - 20 * 44100) {
        asked_for_next_track = true;
        tellmate("ctc:spotify.spool()");
    }

    return num_frames;
}

SP_CALLCONV static void sp_error_occurred(sp_session *session, sp_error error) {
    HERR(error);
}

SP_CALLCONV static void notify_main_thread(sp_session *session) {
    tellmate("ctc:spotify.process_events()");
}

SP_CALLCONV static void end_of_track(sp_session *session) {       assert(is_lua_thread());
    if (loaded_track)
        sp_track_release(loaded_track);
    if (prefetched_track) {
        loaded_track = prefetched_track;
        prefetched_track = NULL;
        if (sp_track_error(loaded_track) == SP_ERROR_OK) {
            ffs_go(process_events_L);
        } else {
            fprintf(stderr, "Still waiting on metdata\n");
            waiting_for_metadata = true;
        }
    } else {
        // TODO call the next track function again anyway
        // NOTE *this* is indeed invoked on the main thread
        lua_spotify_stop(process_events_L);
        lua_rawgeti(process_events_L, LUA_REGISTRYINDEX, callback_onexhaust);
        lua_call(process_events_L, 0, 0);
    }
}

static const char *getstate() {
    switch (sp_session_connectionstate(session)) {
        case SP_CONNECTION_STATE_LOGGED_OUT:   return "loggedout";
        case SP_CONNECTION_STATE_LOGGED_IN:    return "loggedin";
        case SP_CONNECTION_STATE_DISCONNECTED:
        case SP_CONNECTION_STATE_OFFLINE:      return "offline";
        case SP_CONNECTION_STATE_UNDEFINED:
        default:                               return "unknown";
    }
}

SP_CALLCONV static void connectionstate_updated(sp_session *sess) {
    assert(is_lua_thread());

    lua_State *L = process_events_L;
    if (callback_usability_status_change) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, callback_usability_status_change);
        lua_pushstring(L, getstate());
        lua_call(L, 1, 0);
    }
}

sp_session_callbacks session_callbacks = {
    .notify_main_thread = &notify_main_thread,
    .connectionstate_updated = &connectionstate_updated,

    .logged_in = &spcb_logged_in,

    .play_token_lost = NULL,

    .metadata_updated = &metadata_updated,
    .start_playback = NULL,
    .get_audio_buffer_stats = NULL,
    .music_delivery = &music_delivery,
    .stop_playback = NULL,
    .end_of_track = &end_of_track,

    .streaming_error = &sp_error_occurred,
    .offline_error = &sp_error_occurred,
    .scrobble_error = &sp_error_occurred,
    .connection_error = &sp_error_occurred
};


SP_CALLCONV static void search_complete(sp_search *search, void *userdata) {
    assert(is_lua_thread());

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

static int lua_spotify_search(lua_State *L) {         assert(is_lua_thread());
    lua_pushvalue(L, 2);
    sp_search_create(session,
                     luaL_checkstring(L, 1),
                     0, 200, 0, 0, 0, 0, 0, 0, SP_SEARCH_STANDARD,
                     &search_complete,
                     (void *)luaL_ref(L, LUA_REGISTRYINDEX));
    return 0;
}

static int lua_spotify_process_events(lua_State *L) { assert(is_lua_thread());
    process_events_L = L;
    int timeout = 0;
    while (timeout == 0)
        sp_session_process_events(session, &timeout);
    return 0;
}

static int lua_spotify_play(lua_State *L) {           assert(is_lua_thread());
    #define foo(token) \
        if (callback_ ## token) luaL_unref(L, LUA_REGISTRYINDEX, callback_ ## token); \
        lua_pushliteral(L, #token); \
        lua_gettable(L, -2); \
        callback_ ## token = luaL_ref(L, LUA_REGISTRYINDEX)
    foo(next);
    foo(ontrack);
    foo(onexhaust);
    #undef foo

    sp_session_player_play(session, false);
    sp_session_player_unload(session);
    if (al_source) {
        alSourceStop(al_source);
        alSourcei(al_source, AL_BUFFER, 0); // detach buffers
    }
    if (loaded_track) sp_track_release(loaded_track);
    if (prefetched_track) sp_track_release(prefetched_track);
    prefetched_track = NULL;

    sp_link *link = sp_link_create_from_string(luaL_checkstring(L, 1));
    if (!link) return luaL_error(L, "Invalid link");
    sp_track_add_ref(loaded_track = sp_link_as_track(link));
    sp_link_release(link);
    sp_error err = sp_track_error(loaded_track);
    if (err == SP_ERROR_OK) {
        ffs_go(L);
    } else if (err == SP_ERROR_IS_LOADING) {
        waiting_for_metadata = true;
    } else
        HERR(err);
    return 0;
}

static int lua_spotify_pause(lua_State *L) {          assert(is_lua_thread());
    if (loaded_track && lua_gettop(L) == 1) {
        const bool pause = lua_toboolean(L, 1);
        sp_session_player_play(session, !pause);
        if (pause) alSourcePause(al_source); else alSourcePlay(al_source);
    }
    return 0;
}

static int lua_spotify_stop(lua_State *L) {           assert(is_lua_thread());
    sp_session_player_play(session, false);
    sp_session_player_unload(session);
    if (al_device) {
        alSourceStop(al_source);
        alSourcei(al_source, AL_BUFFER, 0); // detach buffers
        alDeleteBuffers(AL_NUM_BUFFERS, al_buffers);
        alDeleteSources(1, &al_source);
        alcDestroyContext(al_context);
        alcCloseDevice(al_device);
        al_device = NULL; }
    if (loaded_track) sp_track_release(loaded_track);
    if (prefetched_track) sp_track_release(prefetched_track);
    prefetched_track = loaded_track = NULL;
    return 0;
}

static int lua_spotify_prefetch(lua_State *L) {       assert(is_lua_thread());
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
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback_next);
    E_LUA_PCALL(L, 0, 1);
    lua_spotify_prefetch(L);
    return 0;
}

static int lua_spotify_login(lua_State *L) {          assert(is_lua_thread());
    if (lua_gettop(L) >= 1) {
        lua_pushliteral(L, "onchange");
        lua_gettable(L, -2);
        callback_usability_status_change = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    if (!session) {
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
    }
    if (sp_username && sp_password) {
        sp_session_login(session, sp_username, sp_password, true, NULL);
        free(sp_username);
        free(sp_password);
        sp_username = sp_password = NULL;
    } else {
        HERR(sp_session_relogin(session));
    }
    return 0;
}

static int lua_spotify_logout(lua_State *L) {         assert(is_lua_thread());
    if (session) {
        lua_spotify_stop(L);
        sp_session_logout(session);
    }
    return 0;
}

static int lua_spotify_getstate(lua_State *L) {       assert(is_lua_thread());
    lua_pushstring(L, getstate());
    return 1;
}

int luaopen_spotify(lua_State *L) {                   assert(is_lua_thread());
    luaL_register(L, "spotify", (struct luaL_reg[]){
        {"login", lua_spotify_login},
        {"logout", lua_spotify_logout},
        {"search", lua_spotify_search},
        {"process_events", lua_spotify_process_events},
        {"play", lua_spotify_play},
        {"prefetch", lua_spotify_prefetch},
        {"spool", lua_spotify_spool},
        {"getstate", lua_spotify_getstate},
        {"pause", lua_spotify_pause},
        {"stop", lua_spotify_stop},
        {NULL, NULL},
    });

    return 1;
}
