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
typedef struct mpv_node mpv_node;
typedef struct { int num; mpv_node *values; char **keys; } mpv_node_list;
typedef struct { void *data; size_t size; } mpv_byte_array;
struct mpv_node {
    union { char *string; int flag; long long int64; double number;
        mpv_node_list *list; mpv_byte_array *bytes; } u;
    int format;
};
static mpv_handle *(*create)(void);
static int (*initialize)(mpv_handle *);
static int (*option)(mpv_handle *, const char *, const char *);
static int (*command)(mpv_handle *, const char **);
static char *(*property)(mpv_handle *, const char *);
static void (*release)(void *);
static void (*destroy)(mpv_handle *);
static mpv_event *(*event)(mpv_handle *, double);
static int (*command_ret)(mpv_handle *, const char **, mpv_node *);
static void (*free_node)(mpv_node *);

static double number(mpv_handle *p, const char *name) {
    char *value = property(p, name);
    double result = value ? atof(value) : -1;
    release(value);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) { fprintf(stderr, "usage: smoke /absolute/libmpv.so video [expected-seek-position|--thumbnail]\n"); return 2; }
    int thumbnail_mode = argc == 4 && strcmp(argv[3], "--thumbnail") == 0;
    double expected_seek = argc == 4 && !thumbnail_mode ? atof(argv[3]) : 2;
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
    LOAD(command_ret, "mpv_command_ret"); LOAD(free_node, "mpv_free_node_contents");
    mpv_handle *p = create();
    if (!p) return 2;
    option(p, "vo", "null"); option(p, "ao", "null"); option(p, "hwdec", "no");
    option(p, "config", "no"); option(p, "terminal", "yes");
    option(p, "msg-level", "all=warn"); option(p, "keep-open", "yes");
    if (thumbnail_mode) {
        option(p, "aid", "no"); option(p, "sid", "no"); option(p, "pause", "yes");
    }
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
    if (thumbnail_mode) {
        int passed = 0, w = 0, h = 0;
        size_t size = 0;
        for (int i = 0; i < 50 && !passed; ++i) {
            event(p, .1);
            mpv_node image = {0};
            const char *shot[] = {"screenshot-raw", "video", NULL};
            if (command_ret(p, shot, &image) >= 0 && image.format == 8) {
                mpv_node_list *map = image.u.list;
                for (int j = 0; j < map->num; ++j) {
                    mpv_node value = map->values[j];
                    if (value.format == 4 && strcmp(map->keys[j], "w") == 0) w = value.u.int64;
                    if (value.format == 4 && strcmp(map->keys[j], "h") == 0) h = value.u.int64;
                    if (value.format == 9 && strcmp(map->keys[j], "data") == 0) size = value.u.bytes->size;
                }
                passed = w > 0 && h > 0 && size >= (size_t)w * h * 4;
            }
            free_node(&image);
        }
        double duration = number(p, "duration");
        passed = passed && duration > 0;
        printf("thumbnail=%s duration=%.3f width=%d height=%d bytes=%zu\n",
            passed ? "PASS" : "FAIL", duration, w, h, size);
        destroy(p);
        return passed ? 0 : 1;
    }
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
