"""Fetch the exact sources used by Kivo's Android libmpv build (Python 3.10+)."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request


def prepare(work: Path, ndk: Path):
    lock = json.loads(Path(__file__).with_name('sources.lock.json').read_text())
    scripts = work / 'upstream' / 'buildscripts'

    def fetch(item):
        name, source = item
        dest = work / 'upstream' if name == 'upstream' else scripts / 'deps' / name
        marker = dest / '.kivo-source'
        if marker.exists():
            if marker.read_text() != source['revision']:
                raise RuntimeError(f'Source changed: use a new work directory: {dest}')
            return
        if dest.exists():
            raise RuntimeError(f'Refusing to replace an existing source directory: {dest}')
        cache = work / 'downloads'
        cache.mkdir(parents=True, exist_ok=True)
        archive = cache / f'{name}-{source["revision"]}.tar.gz'
        if not archive.exists():
            url = f'https://codeload.github.com/{source["repository"]}/tar.gz/{source["revision"]}'
            partial = archive.with_suffix('.partial')
            print(f'Downloading {name} {source["revision"]}', flush=True)
            with urllib.request.urlopen(url, timeout=120) as response, partial.open('wb') as out:
                shutil.copyfileobj(response, out)
            partial.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != source['archiveSha256']:
            raise RuntimeError(f'Source archive checksum mismatch: {archive}')
        staging = work / f'extract-{name}'
        staging.mkdir(exist_ok=True)
        with tarfile.open(archive) as tar:
            # The unused encoder/GPL flavour contains a broken external
            # symlink. It is not part of this build; keep safe extraction on.
            members = [m for m in tar.getmembers()
                       if '/buildscripts/patches-encoders-gpl' not in m.name]
            tar.extractall(staging, members=members, filter='data')
        children = list(staging.iterdir())
        if len(children) != 1 or not children[0].is_dir():
            raise RuntimeError(f'Unexpected archive layout: {archive}')
        dest.parent.mkdir(parents=True, exist_ok=True)
        children[0].rename(dest)
        staging.rmdir()
        marker.write_text(source['revision'])

    # Upstream contains the directory that will hold the other sources.
    fetch(('upstream', lock['upstream']))
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, ((name, src) for name, src in lock.items() if name != 'upstream')))

    if 'Pkg.Revision = 25.2.9519653' not in (ndk / 'source.properties').read_text():
        raise RuntimeError('This recipe requires the pinned Android NDK r25c (25.2.9519653).')
    sdk_ndk = scripts / 'sdk/android-sdk-linux/ndk/25.2.9519653'
    sdk_ndk.parent.mkdir(parents=True, exist_ok=True)
    if not sdk_ndk.exists():
        sdk_ndk.symlink_to(ndk.resolve(), target_is_directory=True)

    ready = work / '.kivo-prepared'
    signature = hashlib.sha256(
        Path(__file__).read_bytes() +
        Path(__file__).with_name('sources.lock.json').read_bytes()
    ).hexdigest()
    if ready.exists():
        if ready.read_text() != signature:
            raise RuntimeError('The build recipe changed; use a new work directory.')
        return
    for dependency in sorted((scripts / 'patches').iterdir()):
        for patch in sorted(dependency.glob('*.patch')):
            subprocess.run(['patch', '-p1', '-i', str(patch.resolve())],
                           cwd=scripts / 'deps' / dependency.name, check=True)
    # Use the existing small build, with the missing RealMedia decoders added.
    # ra_144/ra_288, AAC, AC-3 and ATRAC are already enabled upstream.
    ffmpeg = (scripts / 'flavors/default.sh').read_text()
    anchor = '\t--enable-decoder=wmv* \\\n'
    if ffmpeg.count(anchor) != 1:
        raise RuntimeError('The upstream FFmpeg recipe changed; review the codec patch.')
    extra = ''.join(f'\t--enable-decoder={codec} \\\n' for codec in ('rv10', 'rv20', 'rv30', 'rv40', 'cook', 'sipr'))
    (scripts / 'scripts/ffmpeg.sh').write_text(ffmpeg.replace(anchor, anchor + extra))
    build = scripts / 'build.sh'
    build.write_text(build.read_text().replace('sudo chmod +x', 'chmod +x'))
    for script in (scripts / 'scripts').glob('*.sh'):
        script.chmod(0o755)
    ready.write_text(signature)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--ndk', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.work.resolve(), args.ndk.resolve())
