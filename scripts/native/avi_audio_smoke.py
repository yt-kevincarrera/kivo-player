"""Compare AVI PCM output and verify that timestamp recovery retains audio.

Run after avi_smoke.py has compiled its smoke binary. Uses a baseline and a
patched Android archive of the same ABI; never writes to the original media files.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import uuid
import zipfile


def wav(path):
    raw = path.read_bytes()
    if raw[:4] != b'RIFF' or raw[8:12] != b'WAVE':
        raise ValueError('Expected a finalized PCM/WAVE file')
    offset = 12
    config = data = None
    while offset + 8 <= len(raw):
        name, size = struct.unpack_from('<4sI', raw, offset)
        payload = raw[offset + 8:offset + 8 + size]
        if name == b'fmt ':
            tag, channels, rate, _, _, bits = struct.unpack_from('<HHIIHH', payload)
            if tag == 0xfffe:
                tag = struct.unpack_from('<H', payload, 24)[0]
            config = {'format': tag, 'channels': channels, 'rate': rate, 'bits': bits}
        if name == b'data':
            data = payload
        offset += 8 + size + (size & 1)
    if config is None or not data:
        raise ValueError('Missing WAV format or decoded audio samples')
    return config, data


def signal(config, data, start=0, end=None):
    stride = config['channels'] * config['bits'] // 8
    first = int(start * config['rate']) * stride
    last = int(end * config['rate']) * stride if end is not None else len(data)
    segment = data[first:last]
    if config['format'] == 3 and config['bits'] == 32:
        return any(abs(value[0]) > 0.00001 for value in struct.iter_unpack('<f', segment))
    if config['format'] == 1 and config['bits'] == 16:
        return any(abs(value[0]) > 1 for value in struct.iter_unpack('<h', segment))
    raise ValueError(f'Unhandled test PCM format: {config}')


def retained_with_silence(config, baseline, patched):
    """Require every baseline PCM frame in order, allowing only inserted silence.

    Timestamp holes can occur inside the track as well as at its beginning.
    Split a block crossing a hole down to complete interleaved sample frames.
    """
    stride = config['channels'] * config['bits'] // 8
    cursor = 0

    def match(chunk):
        nonlocal cursor
        if patched[cursor:cursor + len(chunk)] == chunk:
            cursor += len(chunk)
            return True
        found = patched.find(chunk, cursor)
        if found >= 0 and found % stride == 0 and not any(patched[cursor:found]):
            cursor = found + len(chunk)
            return True
        if len(chunk) <= stride:
            return False
        half = (len(chunk) // (2 * stride)) * stride
        return match(chunk[:half]) and match(chunk[half:])

    block = 1024 * stride
    return (len(baseline) % stride == 0 and len(patched) % stride == 0 and
            all(match(baseline[i:i + block]) for i in range(0, len(baseline), block)) and
            not any(patched[cursor:]))


def main(args):
    args.work.mkdir(parents=True, exist_ok=True)
    adb = [args.adb, '-s', args.serial]
    remote = '/data/local/tmp/kivo-avi-audio-' + uuid.uuid4().hex[:12]
    checks = []
    report = {
        'createdAt': datetime.now(timezone.utc).isoformat(),
        'baselineSha256': hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        'patchedSha256': hashlib.sha256(args.patched.read_bytes()).hexdigest(),
        'harnessSha256': hashlib.sha256(args.smoke.read_bytes()).hexdigest(),
        'remoteDirectory': remote,
        'checks': checks,
    }

    def save():
        (args.work / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

    def run(command, **kwargs):
        try:
            return subprocess.run([str(x) for x in command], check=True, timeout=60, **kwargs)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            report['error'] = str(error)
            report['errorStdout'] = str(getattr(error, 'stdout', ''))
            report['errorStderr'] = str(getattr(error, 'stderr', ''))
            save()
            raise

    run([*adb, 'shell', 'mkdir', '-p', remote])
    run([*adb, 'push', args.smoke, remote + '/smoke'], capture_output=True)
    run([*adb, 'shell', 'chmod', '755', remote + '/smoke'])
    media = [('healthy', args.healthy), ('ac3', args.ac3), ('sync', args.sync)]
    for label, path in media:
        run([*adb, 'push', path, remote + '/' + label + '.avi'], capture_output=True)
    outputs = {}
    for version, archive in [('baseline', args.baseline), ('patched', args.patched)]:
        libs = args.work / version
        libs.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as source:
            for name in source.namelist():
                if name.endswith('.so'):
                    (libs / Path(name).name).write_bytes(source.read(name))
        run([*adb, 'push', str(libs) + '/.', remote], capture_output=True)
        for label, _ in media:
            output = f'{version}-{label}.wav'
            result = run([
                *adb, 'shell', 'timeout', '40', 'env', 'LD_LIBRARY_PATH=' + remote,
                remote + '/smoke', remote + '/libmpv.so', remote + '/' + label + '.avi',
                '--audio-dump', 'ao', 'pcm', 'ao-pcm-file', remote + '/' + output,
                'audio-format', 'float', 'audio-channels', 'stereo',
                'untimed', 'yes', 'keep-open', 'no',
            ], capture_output=True, text=True)
            path = args.work / output
            run([*adb, 'pull', remote + '/' + output, path], capture_output=True)
            try:
                config, data = wav(path)
            except (ValueError, struct.error) as error:
                report['error'] = str(error)
                report['failedWave'] = str(path)
                report['nativeOutput'] = result.stdout + result.stderr
                save()
                raise
            outputs[(version, label)] = (config, data)
            check = {'version': version, 'sample': label, 'format': config,
                     'dataBytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                     'output': result.stdout + result.stderr}
            checks.append(check)
            save()
            print(f'{version} {label}: {len(data)} PCM bytes', flush=True)
    healthy_same = outputs[('baseline', 'healthy')] == outputs[('patched', 'healthy')]
    ac3_config, ac3_data = outputs[('patched', 'ac3')]
    sync_config, sync_data = outputs[('patched', 'sync')]
    assertions = {
        'healthyAudioUnchanged': healthy_same,
        'healthyHasAudioSignal': signal(*outputs[('patched', 'healthy')]),
        'ac3MissingIntervalSilent': not signal(ac3_config, ac3_data, 0, 1.60),
        'ac3ValidAudioRetained': signal(ac3_config, ac3_data, 1.70),
        'ac3AllBaselineSamplesRetained': (
            outputs[('baseline', 'ac3')][0] == ac3_config and
            retained_with_silence(ac3_config, outputs[('baseline', 'ac3')][1], ac3_data)),
        'syncMissingIntervalSilent': not signal(sync_config, sync_data, 1, 12),
        'syncValidAudioRetained': signal(sync_config, sync_data, 13.10),
    }
    report['assertions'] = assertions
    save()
    print(json.dumps(assertions, indent=2), flush=True)
    return 0 if all(assertions.values()) else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--smoke', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--patched', type=Path, required=True)
    parser.add_argument('--healthy', type=Path, required=True)
    parser.add_argument('--ac3', type=Path, required=True)
    parser.add_argument('--sync', type=Path, required=True)
    parser.add_argument('--work', type=Path, default=Path('build/avi-audio-smoke'))
    raise SystemExit(main(parser.parse_args()))
