"""Package libmpv with the unchanged, checksum-pinned media_kit JNI helper."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import urllib.request
import zipfile

ABIS = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7l', 'x86_64': 'x86_64', 'x86': 'x86'}
ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_elf(data, abi=None):
    if data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] != 1:
        raise ValueError('Expected a little-endian ELF library')
    machines = {'arm64-v8a': 183, 'armeabi-v7a': 40, 'x86_64': 62, 'x86': 3}
    if abi and struct.unpack_from('<H', data, 18)[0] != machines[abi]:
        raise ValueError(f'ELF architecture does not match {abi}')
    is64 = data[4] == 2
    offset = struct.unpack_from('<Q' if is64 else '<I', data, 32 if is64 else 28)[0]
    size, count = struct.unpack_from('<HH', data, 54 if is64 else 42)
    loads = []
    for i in range(count):
        start = offset + i * size
        if struct.unpack_from('<I', data, start)[0] == 1:
            align = struct.unpack_from('<Q' if is64 else '<I', data, start + (48 if is64 else 28))[0]
            loads.append(align)
    if not loads or min(loads) < 16384:
        raise ValueError('Native library must retain 16 KB page alignment')


def package(work, cache, output, abis=ABIS):
    lock = json.loads(Path(__file__).with_name('base-artifacts.lock.json').read_text())
    artifacts = []
    cache.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    for abi in abis:
        base = cache / f'default-{abi}.jar'
        if not base.exists():
            urllib.request.urlretrieve(lock[abi]['url'], base)
        if digest(base) != lock[abi]['sha256']:
            raise ValueError(f'Base JNI helper archive checksum mismatch: {base}')
        lib = work / f'upstream/buildscripts/prefix/{abi}/lib/libmpv.so'
        data = lib.read_bytes()
        verify_elf(data, abi)
        dest = output / f'realmedia-{abi}.jar'
        with zipfile.ZipFile(base) as original, zipfile.ZipFile(dest, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as result:
            for name in sorted(original.namelist()):
                if not name.endswith('.so'):
                    raise ValueError(f'Unexpected base archive entry: {name}')
                content = data if name == f'lib/{abi}/libmpv.so' else original.read(name)
                verify_elf(content, abi)
                info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                result.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        artifacts.append({'abi': abi, 'file': dest.name, 'sha256': digest(dest),
                          'sizeBytes': dest.stat().st_size, 'libmpvBytes': len(data),
                          'baseSizeBytes': base.stat().st_size})
        print(f'{abi}: {dest.stat().st_size:,} bytes (base {base.stat().st_size:,})')
    manifest = {'recipe': 'realmedia-v1', 'upstream': 'fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768',
                'addedDecoders': ['rv10', 'rv20', 'rv30', 'rv40', 'cook', 'sipr'], 'artifacts': artifacts}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--base-cache', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'third_party/media_kit_libs_android_video/native')
    parser.add_argument('--abi', choices=ABIS, action='append')
    args = parser.parse_args()
    package(args.work, args.base_cache, args.output, args.abi or ABIS)
