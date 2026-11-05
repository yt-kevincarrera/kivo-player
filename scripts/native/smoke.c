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

static double monotonic_seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

static int seek_paused(mpv_handle *p, double target, double expected) {
    const char *pause[] = {"set", "pause", "yes", NULL};
    command(p, pause);
    for (int i = 0; i < 1000 && event(p, 0)->event_id != 0; ++i) {}
    char value[32];
    snprintf(value, sizeof(value), "%.6f", target);
    const char *seek[] = {"seek", value, "absolute+exact", NULL};
    if (command(p, seek) < 0) return 0;
    int restarted = 0;
    for (int i = 0; i < 100; ++i) {
        if (event(p, .1)->event_id == 21) restarted = 1;
        double position = number(p, "time-pos");
        if (restarted && position >= expected - .15 && position <= expected + .15)
            return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3 || (argc > 3 && argc % 2 != 0)) { fprintf(stderr, "usage: smoke /absolute/libmpv.so video [expected-seek-position|--thumbnail|--realtime|--timeline|--seek-roundtrip|--audio-dump|--video-only|--realtime-video-only] [option value ...]\n"); return 2; }
    int thumbnail_mode = argc >= 4 && strcmp(argv[3], "--thumbnail") == 0;
    int seek_roundtrip_mode = argc >= 4 && strcmp(argv[3], "--seek-roundtrip") == 0;
    int audio_dump_mode = argc >= 4 && strcmp(argv[3], "--audio-dump") == 0;
    int timeline_mode = argc >= 4 && strcmp(argv[3], "--timeline") == 0;
    int realtime_mode = timeline_mode || (argc >= 4 && (strcmp(argv[3], "--realtime") == 0 || strcmp(argv[3], "--realtime-video-only") == 0));
    int video_only = argc >= 4 && (strcmp(argv[3], "--video-only") == 0 || strcmp(argv[3], "--realtime-video-only") == 0);
    double expected_seek = argc >= 4 && !thumbnail_mode && !realtime_mode && !video_only && !seek_roundtrip_mode ? atof(argv[3]) : 2;
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
    for (int i = 4; i + 1 < argc; i += 2) {
        if (option(p, argv[i], argv[i + 1]) < 0) {
            fprintf(stderr, "invalid test option %s=%s\n", argv[i], argv[i + 1]);
            destroy(p);
            return 2;
        }
    }
    if (initialize(p) < 0) { destroy(p); return 2; }
    char *version = property(p, "mpv-version");
    printf("mpv-version=%s\n", version ? version : "unavailable");
    release(version);
    if (strcmp(argv[2], "--version") == 0) { destroy(p); return 0; }
    if (strcmp(argv[2], "--decoder-list") == 0) {
        char *list = property(p, "decoder-list");
        printf("%s\n", list ? list : "unavailable");
        release(list);
        destroy(p);
        return 0;
    }
    if (strcmp(argv[2], "--decoders") == 0) {
        const char *required[] = {"rv10", "rv20", "rv30", "rv40", "cook", "sipr", "cinepak"};
        char *list = property(p, "decoder-list");
        int missing = 0;
        for (unsigned i = 0; i < sizeof(required) / sizeof(required[0]); ++i) {
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
    if (audio_dump_mode) {
        int passed = 0;
        double deadline = monotonic_seconds() + 30;
        while (monotonic_seconds() < deadline) {
            mpv_event *e = event(p, .1);
            if (e->event_id == 7) {
                // mpv_event_end_file starts with its integer reason. EOF = 0.
                passed = e->data && *(int *)e->data == 0;
                break;
            }
        }
        destroy(p); // finalize the PCM output header before inspecting it
        printf("audio-dump=%s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
    if (thumbnail_mode) {
        int passed = 0, w = 0, h = 0;
        size_t size = 0;
        for (int i = 0; i < 50 && !passed; ++i) {
            int ended = event(p, .1)->event_id == 7; // MPV_EVENT_END_FILE
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
            if (ended) break;
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
        int ended = event(p, .1)->event_id == 7;
        duration = number(p, "duration");
        position = number(p, "time-pos");
        width = number(p, "video-dec-params/w");
        rate = number(p, "audio-params/samplerate");
        if (duration > 0 && position >= .5 && width > 0 && (video_only || rate > 0)) { decoded = 1; break; }
        if (ended) break;
    }
    printf("decode=%s duration=%.3f position=%.3f width=%.0f audio-rate=%.0f\n", decoded ? "PASS" : "FAIL", duration, position, width, rate);
    if (realtime_mode) {
        double start = monotonic_seconds(), initial = position;
        double elapsed = 0;
        double requested_speed = number(p, "speed");
        if (requested_speed <= 0) requested_speed = 1;
        double window = timeline_mode ? 8 : 3;
        if (timeline_mode && (duration - initial) / requested_speed - .25 < window)
            window = (duration - initial) / requested_speed - .25;
        double previous = initial, max_skew = 0;
        int backwards = 0, resets = 0;
        while (decoded && elapsed < window) {
            event(p, .05);
            elapsed = monotonic_seconds() - start;
            if (timeline_mode) {
                double current = number(p, "time-pos");
                double skew = number(p, "avsync");
                if (skew < 0) skew = -skew;
                if (skew > max_skew) max_skew = skew;
                if (current >= 0) {
                    if (previous - current > .25) backwards++;
                    if (previous >= .75 && current < .25) resets++;
                    if (current != previous)
                        printf("timeline wall=%.3f position=%.3f avsync=%.3f\n", elapsed, current, number(p, "avsync"));
                    previous = current;
                }
            }
        }
        position = number(p, "time-pos");
        double speed = elapsed > 0 ? (position - initial) / elapsed : 0;
        double avsync = number(p, "avsync");
        int passed = decoded && window >= .25 &&
            speed >= .85 * requested_speed && speed <= 1.15 * requested_speed &&
            (video_only || (avsync >= -.25 && avsync <= .25));
        if (timeline_mode) {
            passed = passed && backwards == 0 && resets == 0 && max_skew <= .25;
            printf("timeline=%s backwards=%d resets-to-start=%d max-avsync=%.3f\n",
                passed ? "PASS" : "FAIL", backwards, resets, max_skew);
        }
        printf("realtime=%s media-seconds=%.3f wall-seconds=%.3f speed=%.3f requested-speed=%.3f avsync=%.3f decoder-fps=%.3f dropped-frames=%.0f\n",
            passed ? "PASS" : "FAIL", position - initial, elapsed, speed, requested_speed, avsync,
            number(p, "estimated-vf-fps"), number(p, "frame-drop-count"));
        destroy(p);
        return passed ? 0 : 1;
    }
    int sought = 0;
    if (decoded) {
        sought = seek_paused(p, 2, expected_seek);
        position = number(p, "time-pos");
        if (seek_roundtrip_mode && sought) {
            const double targets[] = {.5, 3};
            for (unsigned i = 0; i < sizeof(targets) / sizeof(targets[0]); ++i) {
                int passed = seek_paused(p, targets[i], targets[i]);
                position = number(p, "time-pos");
                printf("seek-target=%.3f result=%s position=%.3f\n",
                    targets[i], passed ? "PASS" : "FAIL", position);
                if (!passed) sought = 0;
                if (passed && i == 0) {
                    // Seeking backwards must also restore audio sync when
                    // playback resumes, not just place a paused video frame.
                    const char *resume[] = {"set", "pause", "no", NULL};
                    command(p, resume);
                    double start = monotonic_seconds();
                    while (monotonic_seconds() - start < 1) event(p, .05);
                    double elapsed = monotonic_seconds() - start;
                    double requested = number(p, "speed");
                    double expected = targets[i] + requested * elapsed;
                    position = number(p, "time-pos");
                    double skew = number(p, "avsync");
                    int resumed = position >= expected - .25 &&
                        position <= expected + .25 && skew >= -.25 && skew <= .25;
                    printf("seek-resume=%s expected=%.3f position=%.3f avsync=%.3f\n",
                        resumed ? "PASS" : "FAIL", expected, position, skew);
                    if (!resumed) sought = 0;
                }
            }
        }
    }
    printf("seek=%s position=%.3f\n", sought ? "PASS" : "FAIL", position);
    destroy(p);
    return decoded && sought ? 0 : 1;
}
