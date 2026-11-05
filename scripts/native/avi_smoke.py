"""Check AVI playback with the Android libmpv shipped in Kivo (no UI or sound).

Uses hash-pinned public FFmpeg samples and optional local/synthetic AVI files.
Every result is recorded, including failures; this does not certify a phone's
hardware decoder or Flutter video surface.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import urllib.request
import uuid
import zipfile

from smoke import ROOT, TARGETS


def run_matrix(args):
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    adb = [args.adb, '-s', args.serial]

    def run(command, **kwargs):
        return subprocess.run([str(x) for x in command], check=True,
                              timeout=60, **kwargs)

    boot = run([*adb, 'shell', 'getprop', 'sys.boot_completed'],
               capture_output=True, text=True).stdout.strip()
    if boot != '1':
        raise RuntimeError('Wait until Android finishes booting before measuring playback.')
    def device_property(name):
        return run([*adb, 'shell', 'getprop', name], capture_output=True, text=True).stdout.strip()
    device = {
        'model': device_property('ro.product.model'),
        'androidRelease': device_property('ro.build.version.release'),
        'sdk': device_property('ro.build.version.sdk'),
        'abi': device_property('ro.product.cpu.abi'),
        'emulator': device_property('ro.kernel.qemu') == '1',
    }
    with zipfile.ZipFile(args.jar) as archive:
        libraries = [n for n in archive.namelist() if n.endswith('/libmpv.so')]
        if len(libraries) != 1:
            raise ValueError('Expected one libmpv per archive')
        abi = libraries[0].split('/')[1]
        native = work / abi
        native.mkdir(exist_ok=True)
        for name in archive.namelist():
            if name.endswith('.so'):
                (native / Path(name).name).write_bytes(archive.read(name))
    host = 'windows-x86_64' if platform.system() == 'Windows' else 'linux-x86_64'
    toolchain = args.ndk / 'toolchains/llvm/prebuilt' / host
    compiler = toolchain / 'bin' / ('clang.exe' if platform.system() == 'Windows' else 'clang')
    binary = work / f'smoke-{abi}'
    run([compiler, f'--target={TARGETS[abi]}-linux-android21',
         f'--sysroot={toolchain / "sysroot"}', Path(__file__).with_name('smoke.c'),
         '-Wl,-z,max-page-size=16384', '-Wall', '-Wextra', '-Werror', '-ldl', '-o', binary])
    remote = f'/data/local/tmp/kivo-avi-{uuid.uuid4().hex[:12]}'
    run([*adb, 'shell', 'mkdir', '-p', remote])
    run([*adb, 'push', str(native) + '/.', remote], capture_output=True)
    run([*adb, 'push', binary, remote + '/smoke'], capture_output=True)
    run([*adb, 'shell', 'chmod', '755', remote + '/smoke'])
    report = {
        'createdAt': datetime.now(timezone.utc).isoformat(),
        'abi': abi, 'serial': args.serial if device['emulator'] else 'physical-device',
        'device': device, 'remoteDirectory': remote,
        'jarSha256': hashlib.sha256(args.jar.read_bytes()).hexdigest(),
        'limits': 'Software decode with null audio/video outputs; no Flutter-surface, audible-output or hardware-decoder proof.',
        'checks': [],
        'nativeOptions': args.native_option,
        'samples': [],
    }

    def check(label, source, mode):
        command = [*adb, 'shell', 'timeout', '40', 'env', f'LD_LIBRARY_PATH={remote}',
                   remote + '/smoke', remote + '/libmpv.so', source, mode]
        for key, value in args.native_option:
            command.extend([key, value])
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            passed = result.returncode == 0
        except subprocess.TimeoutExpired as error:
            output = f'TIMEOUT after {error.timeout}s'
            passed = False
        report['checks'].append({'sample': label, 'mode': mode,
                                 'passed': passed, 'output': output})
        (work / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(f'{label} {mode}: {"PASS" if passed else "FAIL"}', flush=True)
        print(output.strip(), flush=True)

    check('required RealMedia decoders', '--decoders', '2')
    samples = []
    fixtures = json.loads(args.fixtures.read_text(encoding='utf-8'))
    for fixture in fixtures:
        sample = work / fixture['file']
        if not sample.exists():
            with urllib.request.urlopen(fixture['url'], timeout=45) as response:
                sample.write_bytes(response.read())
        if hashlib.sha256(sample.read_bytes()).hexdigest() != fixture['sha256']:
            raise ValueError(f'Fixture checksum mismatch: {sample}')
        samples.append((sample, fixture.get('audio') is not None))
    samples.extend((sample.resolve(), True) for sample in args.extra_file)
    if args.generate:
        generated = work / 'generated'
        generated.mkdir(exist_ok=True)
        recipes = [
            ('mpeg4-mp3.avi', 'mpeg4', 'libmp3lame', '25', '44100', ['-bf', '2']),
            ('msmpeg4-mp3.avi', 'msmpeg4v3', 'libmp3lame', '25', '44100', []),
            ('xvid-mp3.avi', 'libxvid', 'libmp3lame', '25', '44100', ['-bf', '2']),
            ('mjpeg-pcm.avi', 'mjpeg', 'pcm_s16le', '30', '48000', []),
        ]
        for name, video, audio, fps, sample_rate, extra in recipes:
            sample = generated / name
            run([args.ffmpeg, '-hide_banner', '-loglevel', 'error',
                 '-f', 'lavfi', '-i', f'testsrc2=size=640x360:rate={fps}',
                 '-f', 'lavfi', '-i', f'sine=frequency=440:sample_rate={sample_rate}',
                 '-t', '8', '-c:v', video, '-q:v', '5', *extra,
                 '-c:a', audio, '-y', sample])
            samples.append((sample, True))
    for index, (sample, has_audio) in enumerate(samples):
        report['samples'].append({'file': sample.name, 'hasAudio': has_audio,
                                  'sha256': hashlib.sha256(sample.read_bytes()).hexdigest()})
        remote_sample = remote + f'/sample-{index}.avi'
        run([*adb, 'push', sample, remote_sample], capture_output=True)
        check(sample.name, remote_sample, '2' if has_audio else '--video-only')
        check(sample.name, remote_sample, '--thumbnail')
        for _ in range(args.repetitions):
            check(sample.name, remote_sample,
                  '--realtime' if has_audio else '--realtime-video-only')
        if args.check_timeline and has_audio:
            check(sample.name, remote_sample, '--timeline')
        if args.check_seek_roundtrip:
            check(sample.name, remote_sample, '--seek-roundtrip')
    failures = sum(not check['passed'] for check in report['checks'])
    print(f'{len(report["checks"])} checks, {failures} failures. Report: {work / "results.json"}', flush=True)
    return 1 if failures else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path,
                        default=Path(__file__).with_name('avi-fixtures.lock.json'))
    parser.add_argument('--work', type=Path, default=ROOT / 'build/avi-smoke')
    parser.add_argument('--extra-file', type=Path, action='append', default=[],
                        help='Additional local AVI containing both video and audio.')
    parser.add_argument('--generate', action='store_true',
                        help='Generate four additional codec combinations with FFmpeg.')
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--repetitions', type=int, default=2)
    parser.add_argument('--check-timeline', action='store_true')
    parser.add_argument('--check-seek-roundtrip', action='store_true')
    parser.add_argument('--native-option', nargs=2, action='append', default=[],
                        metavar=('NAME', 'VALUE'), help='Set one mpv option for a differential run.')
    options = parser.parse_args()
    if options.repetitions < 1:
        parser.error('--repetitions must be at least 1')
    raise SystemExit(run_matrix(options))
