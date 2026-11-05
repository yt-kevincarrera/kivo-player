#pragma once

#include <math.h>

// A seek clears this offset. Within forward playback a backwards AVI audio
// timestamp is a metadata reset: retain every decoded sample and continue.
struct kivo_avi_audio_clock {
    double offset;
};

static inline double kivo_avi_audio_pts(struct kivo_avi_audio_clock *clock,
                                       double raw, double expected)
{
    if (!isfinite(raw) || !isfinite(expected))
        return raw;
    double pts = raw + clock->offset;
    if (pts < expected - 0.001) {
        clock->offset += expected - pts;
        pts = expected;
    }
    return pts;
}

// Bound both each allocation and the repair interval. Do not synthesize hours
// of silence from a corrupt index; longer gaps keep the original mpv policy.
static inline int kivo_avi_audio_gap_samples(double pts, double expected, int rate)
{
    if (!isfinite(pts) || !isfinite(expected) || rate <= 0)
        return 0;
    double gap = pts - expected;
    if (gap <= 0.001 || gap > 30.0)
        return 0;
    return gap >= 8192.0 / rate ? 8192 : (int)llrint(gap * rate);
}
