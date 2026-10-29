// Android command-line regression test for the same libmpv shipped in the APK.
// Uses a null output to check actual software decoding without an Activity.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct mpv_handle mpv_handle;
typedef struct { int event_id; int error; unsigned long long reply_userdata; void *data; } mpv_event;
static mpv_handle *(*create)(void);
static int (*initialize)(mpv_handle *);
static int (*option)(mpv_handle *, const char *, const char *);
static int (*command)(mpv_handle *, const char **);
static char *(*property)(mpv_handle *, const char *);
static void (*release)(void *);
static void (*destroy)(mpv_handle *);
static mpv_event *(*event)(mpv_handle *, double);

static double number(mpv_handle *p, const char *name) {
    char *value = property(p, name);
    double result = value ? atof(value) : -1;
    release(value);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) { fprintf(stderr, "usage: smoke /absolute/libmpv.so video [expected-seek-position]\n"); return 2; }
    double expected_seek = argc == 4 ? atof(argv[3]) : 2;
    void *lib = dlopen(argv[1], RTLD_NOW);
    if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 2; }
    // The Dart/Android video bridge needs these exports as well as playback.
    const char *bridge_api[] = {"mpv_lavc_set_java_vm", "mpv_render_context_create", "mpv_render_context_render"};
    for (int i = 0; i < 3; ++i) {
        if (!dlsym(lib, bridge_api[i])) { fprintf(stderr, "missing bridge API %s\n", bridge_api[i]); return 2; }
    }
#define LOAD(target, name) do { *(void **)(&target) = dlsym(lib, name); if (!target) { fprintf(stderr, "missing %s\n", name); return 2; } } while (0)
    LOAD(create, "mpv_create"); LOAD(initialize, "mpv_initialize");
    LOAD(option, "mpv_set_option_string"); LOAD(command, "mpv_command");
    LOAD(property, "mpv_get_property_string"); LOAD(release, "mpv_free");
    LOAD(destroy, "mpv_terminate_destroy"); LOAD(event, "mpv_wait_event");
    mpv_handle *p = create();
    if (!p) return 2;
    option(p, "vo", "null"); option(p, "ao", "null"); option(p, "hwdec", "no");
    option(p, "config", "no"); option(p, "terminal", "yes");
    option(p, "msg-level", "all=warn"); option(p, "keep-open", "yes");
    if (initialize(p) < 0) { destroy(p); return 2; }
    char *version = property(p, "mpv-version");
    printf("mpv-version=%s\n", version ? version : "unavailable");
    release(version);
    if (strcmp(argv[2], "--version") == 0) { destroy(p); return 0; }
    if (strcmp(argv[2], "--decoders") == 0) {
        const char *required[] = {"rv10", "rv20", "rv30", "rv40", "cook", "sipr"};
        char *list = property(p, "decoder-list");
        int missing = 0;
        for (int i = 0; i < 6; ++i) {
            int found = list && strstr(list, required[i]);
            printf("decoder %s=%s\n", required[i], found ? "PASS" : "FAIL");
            missing += !found;
        }
        release(list);
        destroy(p);
        return missing ? 1 : 0;
    }
    const char *load[] = {"loadfile", argv[2], NULL};
    if (command(p, load) < 0) { destroy(p); return 1; }
    int decoded = 0;
    double duration = -1, position = -1, width = -1, rate = -1;
    for (int i = 0; i < 150; ++i) {
        event(p, .1);
        duration = number(p, "duration");
        position = number(p, "time-pos");
        width = number(p, "video-dec-params/w");
        rate = number(p, "audio-params/samplerate");
        if (duration > 0 && position >= .5 && width > 0 && rate > 0) { decoded = 1; break; }
    }
    printf("decode=%s duration=%.3f position=%.3f width=%.0f audio-rate=%.0f\n", decoded ? "PASS" : "FAIL", duration, position, width, rate);
    int sought = 0;
    if (decoded) {
        // Pausing prevents ordinary progress from being mistaken for a seek.
        const char *pause[] = {"set", "pause", "yes", NULL};
        command(p, pause);
        while (event(p, 0)->event_id != 0) {}
        const char *seek[] = {"seek", "2", "absolute+exact", NULL};
        if (command(p, seek) >= 0) {
            int restarted = 0;
            for (int i = 0; i < 100; ++i) {
                // MPV_EVENT_PLAYBACK_RESTART: decoding has resumed after seek.
                if (event(p, .1)->event_id == 21) restarted = 1;
                position = number(p, "time-pos");
                if (restarted && position >= expected_seek - .15 && position <= expected_seek + .15) { sought = 1; break; }
            }
        }
    }
    printf("seek=%s position=%.3f\n", sought ? "PASS" : "FAIL", position);
    destroy(p);
    return decoded && sought ? 0 : 1;
}
