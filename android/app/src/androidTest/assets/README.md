`generated.rm` is a synthetic two-second RV10 video for catalog regression tests.
It contains FFmpeg's generated test pattern, without external media or audio.

Regenerate with:

```sh
ffmpeg -f lavfi -i testsrc2=size=64x48:rate=5 -t 2 -c:v rv10 -an -y generated.rm
```
