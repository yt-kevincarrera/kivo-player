"""Verify the checked-in Android native libraries without building Flutter."""
import argparse
import json
from pathlib import Path
import zipfile
from package import ABIS, ROOT, digest, verify_elf


def verify(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if {a['abi'] for a in manifest['artifacts']} != set(ABIS):
        raise ValueError('The native bundle must contain all supported Android ABIs')
    for artifact in manifest['artifacts']:
        jar = directory / artifact['file']
        if jar.name != f'realmedia-{artifact["abi"]}.jar':
            raise ValueError('Unexpected native artifact name')
        if digest(jar) != artifact['sha256']:
            raise ValueError(f'Native archive checksum mismatch: {jar}')
        with zipfile.ZipFile(jar) as z:
            expected = {f'lib/{artifact["abi"]}/{name}' for name in ('libmpv.so', 'libmediakitandroidhelper.so')}
            if set(z.namelist()) != expected:
                raise ValueError(f'Unexpected native archive contents: {jar}')
            for name in z.namelist():
                verify_elf(z.read(name), artifact['abi'])
        print(f'{artifact["abi"]}: SHA-256, ABI, archive contents and 16 KB alignment PASS')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path, default=ROOT / 'third_party/media_kit_libs_android_video/native')
    verify(parser.parse_args().directory)
