#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../scripts/native/avi_audio_clock.h"

static void near(double actual, double expected)
{
    assert(fabs(actual - expected) < 0.0000001);
}

int main(void)
{
    struct kivo_avi_audio_clock clock = {0};

    // A correctly timestamped track, including a deliberate initial offset,
    // keeps its sample timestamps. Metadata rounding needs no padding.
    for (int i = 0; i < 1000; ++i) {
        double pts = 2.0 + i * 1536.0 / 48000;
        near(kivo_avi_audio_pts(&clock, pts, pts), pts);
        assert(kivo_avi_audio_gap_samples(pts + .0005, pts, 48000) == 0);
    }
    near(clock.offset, 0);

    // The real damaged AC-3 fixture loses its first 1.611982 seconds. Cover
    // that interval without moving the valid frame or making a huge buffer.
    double expected = 0, actual = 1.611982;
    int total = 0, count;
    while ((count = kivo_avi_audio_gap_samples(actual, expected, 48000)) > 0) {
        assert(count <= 8192);
        total += count;
        expected += count / 48000.0;
    }
    assert(abs(total - (int)llrint(actual * 48000)) <= 1);
    near(kivo_avi_audio_pts(&clock, actual, expected), actual);

    // A forward jump preserves the later valid audio's intended position.
    near(kivo_avi_audio_pts(&clock, 13.008, .024), 13.008);
    assert(kivo_avi_audio_gap_samples(13.008, .024, 48000) == 8192);

    // A timestamp reset in continuing audio preserves every frame. The new
    // offset applies once, including all following samples in that segment.
    near(kivo_avi_audio_pts(&clock, 0, 13.032), 13.032);
    near(kivo_avi_audio_pts(&clock, .024, 13.056), 13.056);
    near(kivo_avi_audio_pts(&clock, .048, 13.080), 13.080);
    assert(kivo_avi_audio_gap_samples(13.080, 13.080, 48000) == 0);

    // A user seek backwards starts a new timeline rather than retaining the
    // correction from the previous playback interval.
    clock = (struct kivo_avi_audio_clock){0};
    near(kivo_avi_audio_pts(&clock, .5, .5), .5);
    near(kivo_avi_audio_pts(&clock, .524, .524), .524);
    near(clock.offset, 0);

    // Repeated source resets must not rewind the presented clock or discard
    // a frame. This matches the report of a position indicator returning to 0.
    for (int i = 0; i < 1000; ++i) {
        double expected_pts = i * .024;
        double raw_pts = (i % 3) * .024;
        double presented = kivo_avi_audio_pts(&clock, raw_pts, expected_pts);
        near(presented, expected_pts);
        assert(kivo_avi_audio_gap_samples(presented, expected_pts, 48000) == 0);
    }
    clock = (struct kivo_avi_audio_clock){0};

    assert(kivo_avi_audio_gap_samples(3600, 0, 48000) == 0);
    assert(kivo_avi_audio_gap_samples(1, 0, 0) == 0);
    assert(kivo_avi_audio_gap_samples(INFINITY, 0, 48000) == 0);
    assert(kivo_avi_audio_gap_samples(NAN, 0, 48000) == 0);
    assert(kivo_avi_audio_gap_samples(1, 0, 2147483647) == 8192);
    puts("AVI_AUDIO_CLOCK_PASS: healthy audio, gaps, resets, seeks and bounds");
    return 0;
}
