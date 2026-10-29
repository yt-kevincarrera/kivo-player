"""Decode and seek public RealMedia samples with an Android native artifact."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import urllib.request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {'arm64-v8a': 'aarch64', 'armeabi-v7a': 'armv7a', 'x86_64': 'x86_64', 'x86': 'i686'}


def smoke(adb, ndk, serial, jar, work, extra_files):
    def run(args, **kwargs):
        subprocess.run([str(x) for x in args], check=True, **kwargs)

    adb_command = [adb, '-s', serial]
    work.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(jar) as z:
        libraries = [n for n in z.namelist() if n.endswith('/libmpv.so')]
        if len(libraries) != 1:
            raise ValueError('Expected one libmpv per archive')
        abi = libraries[0].split('/')[1]
        native = work / abi
        native.mkdir(exist_ok=True)
        for name in z.namelist():
            if name.endswith('.so'):
                (native / Path(name).name).write_bytes(z.read(name))

    host = 'windows-x86_64' if platform.system() == 'Windows' else 'linux-x86_64'
    toolchain = ndk / 'toolchains/llvm/prebuilt' / host
    compiler = toolchain / 'bin' / ('clang.exe' if platform.system() == 'Windows' else 'clang')
    binary = work / f'smoke-{abi}'
    run([compiler, f'--target={TARGETS[abi]}-linux-android21',
         f'--sysroot={toolchain / "sysroot"}', Path(__file__).with_name('smoke.c'),
         '-Wl,-z,max-page-size=16384', '-ldl', '-o', binary])
    remote = f'/data/local/tmp/kivo-realmedia-{uuid.uuid4().hex[:12]}'
    run([*adb_command, 'shell', 'mkdir', '-p', remote])
    run([*adb_command, 'push', str(native) + '/.', remote], stdout=subprocess.DEVNULL)
    run([*adb_command, 'push', binary, remote + '/smoke'], stdout=subprocess.DEVNULL)
    run([*adb_command, 'shell', 'chmod', '755', remote + '/smoke'])

    def check(argument, expected_seek=2):
        run([*adb_command, 'shell', f'LD_LIBRARY_PATH={remote}', remote + '/smoke',
             remote + '/libmpv.so', argument, str(expected_seek)])

    print(f'Checking enabled decoders ({abi})', flush=True)
    check('--decoders')
    fixtures = json.loads(Path(__file__).with_name('fixtures.lock.json').read_text())
    for fixture in fixtures:
        sample = work / fixture['file']
        if not sample.exists():
            urllib.request.urlretrieve(fixture['url'], sample)
        if hashlib.sha256(sample.read_bytes()).hexdigest() != fixture['sha256']:
            raise ValueError(f'Fixture checksum mismatch: {sample}')
        remote_sample = remote + '/' + fixture['file']
        run([*adb_command, 'push', sample, remote_sample], stdout=subprocess.DEVNULL)
        print(f'{fixture["file"]}: {fixture["video"]}/{fixture["audio"]}', flush=True)
        check(remote_sample, fixture.get('expectedSeekPositionSeconds', 2))
    for index, sample in enumerate(extra_files):
        remote_sample = remote + f'/extra-{index}' + sample.suffix
        run([*adb_command, 'push', sample, remote_sample], stdout=subprocess.DEVNULL)
        print(f'Regression: {sample.name}', flush=True)
        check(remote_sample)
    print('All RealMedia decode/progress/seek checks passed.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--work', type=Path, default=ROOT / 'build/realmedia-smoke')
    parser.add_argument('--extra-file', type=Path, action='append', default=[])
    args = parser.parse_args()
    smoke(args.adb, args.ndk, args.serial, args.jar, args.work, args.extra_file)
