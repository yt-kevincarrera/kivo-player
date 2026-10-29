#!/usr/bin/env bash
# Build on Linux/WSL. Sources are pinned; the compiler is Android NDK r25c.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${KIVO_NATIVE_WORK:?Set KIVO_NATIVE_WORK to an isolated native build directory}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the Linux Android NDK r25c directory}"
export cores="${KIVO_NATIVE_JOBS:-4}"
python3 "$script_dir/prepare.py" --work "$KIVO_NATIVE_WORK" --ndk "$ANDROID_NDK_HOME"
cd "$KIVO_NATIVE_WORK/upstream/buildscripts"
architectures=("${@}")
if [ ${#architectures[@]} -eq 0 ]; then
    architectures=(arm64 armv7l x86_64 x86)
fi
for arch in "${architectures[@]}"; do
    bash build.sh --arch "$arch"
    case "$arch" in
        arm64) abi=arm64-v8a ;;
        armv7l) abi=armeabi-v7a ;;
        x86_64|x86) abi="$arch" ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 2 ;;
    esac
    mkdir -p "$KIVO_NATIVE_WORK/symbols/$abi"
    cp "prefix/$abi/lib/libmpv.so" "$KIVO_NATIVE_WORK/symbols/$abi/libmpv.so"
    "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
        --strip-unneeded "prefix/$abi/lib/libmpv.so"
done
