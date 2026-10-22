#!/usr/bin/env python3
"""Build exact-byte APK deltas using only Python's standard library.

KIVODLT1 is one gzip stream containing a big-endian binary program. Its header
is magic[8], base_size:u64, target_size:u64, base_sha256[32], target_sha256[32].
Commands are END=0, COPY=1 (offset:u64, length:u64), DATA=2 (length:u64, bytes).
COPY reads the installed APK; DATA supplies bytes exactly as they occur in the
signed target APK. ZIP entries are never unpacked/recompressed or re-signed.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import time
from typing import BinaryIO, Iterator
import zipfile

MAGIC = b"KIVODLT1"
MAX_APK_BYTES = 512 * 1024 * 1024
MAX_PATCH_BYTES = 256 * 1024 * 1024
MAX_COMMANDS = 1_000_000
BUFFER_BYTES = 1024 * 1024
PATCH_MAX_RATIO = 0.8
MANIFEST_NAME = "kivo-update-v1.json"
PACKAGE_NAME = "dev.selector.kivo_player"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
APK_NAME = re.compile(
    r"^kivo-v(\d+\.\d+\.\d+)-(arm64-v8a|armeabi-v7a|x86_64)\.apk$"
)


class PatchTooLargeError(ValueError):
    """The full APK remains available when a patch exceeds client limits."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(BUFFER_BYTES), b""):
            digest.update(block)
    return digest.hexdigest()


def _apk_size(path: Path) -> int:
    size = path.stat().st_size
    if not 0 < size <= MAX_APK_BYTES:
        raise ValueError(f"APK size outside supported limits: {path.name}")
    return size


def _read_exact(stream: BinaryIO, length: int) -> bytes:
    data = stream.read(length)
    if len(data) != length:
        raise ValueError("Truncated delta")
    return data


def _u64(stream: BinaryIO) -> int:
    return struct.unpack(">Q", _read_exact(stream, 8))[0]


def _entry_ranges(path: Path, contents: bytes) -> list[tuple[str, int, int, int]]:
    """Return name, local-header offset, raw-data offset, raw-data end."""
    ranges = []
    names: set[str] = set()
    previous_end = 0
    with zipfile.ZipFile(path) as archive:
        for entry in sorted(archive.infolist(), key=lambda item: item.header_offset):
            start = entry.header_offset
            if entry.filename in names:
                raise ValueError("Duplicate APK ZIP entry")
            names.add(entry.filename)
            if start < previous_end or start + 30 > len(contents):
                raise ValueError("Invalid APK ZIP entry bounds")
            if contents[start : start + 4] != b"PK\x03\x04":
                raise ValueError("Invalid APK local ZIP header")
            name_length, extra_length = struct.unpack_from("<HH", contents, start + 26)
            data = start + 30 + name_length + extra_length
            end = data + entry.compress_size
            if data > len(contents) or end > len(contents):
                raise ValueError("Invalid APK ZIP data bounds")
            ranges.append((entry.filename, start, data, end))
            previous_end = end
    return ranges


def _commands(
    base: bytes,
    target: bytes,
    base_ranges: list[tuple[str, int, int, int]],
    target_ranges: list[tuple[str, int, int, int]],
) -> Iterator[tuple[int, int | bytes, int]]:
    """Reuse raw entries, including payloads whose alignment headers changed."""
    by_name = {entry[0]: entry for entry in base_ranges}
    cursor = 0
    for name, start, data, end in target_ranges:
        if cursor < start:
            yield (2, target[cursor:start], 0)
        previous = by_name.get(name)
        if previous is not None:
            _, old_start, old_data, old_end = previous
            if target[start:end] == base[old_start:old_end]:
                yield (1, old_start, end - start)
                cursor = end
                continue
        if data > start:
            yield (2, target[start:data], 0)
        if previous is not None and target[data:end] == base[previous[2] : previous[3]]:
            if end > data:
                yield (1, previous[2], end - data)
        elif end > data:
            yield (2, target[data:end], 0)
        cursor = end
    if cursor < len(target):
        # Includes the APK signing block, central directory, and end record.
        yield (2, target[cursor:], 0)


def generate_patch(base: Path, target: Path, destination: Path) -> dict:
    """Create and independently reconstruct a patch before returning metadata."""
    started = time.perf_counter()
    base_size, target_size = _apk_size(base), _apk_size(target)
    base_bytes, target_bytes = base.read_bytes(), target.read_bytes()
    base_hash = hashlib.sha256(base_bytes).hexdigest()
    target_hash = hashlib.sha256(target_bytes).hexdigest()
    base_ranges = _entry_ranges(base, base_bytes)
    target_ranges = _entry_ranges(target, target_bytes)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    rebuilt = None
    copied = literal = commands = 0
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as raw:
            temporary = Path(raw.name)
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as stream:
                stream.write(MAGIC + struct.pack(">QQ", base_size, target_size))
                stream.write(bytes.fromhex(base_hash) + bytes.fromhex(target_hash))
                for kind, value, length in _commands(
                    base_bytes, target_bytes, base_ranges, target_ranges
                ):
                    commands += 1
                    if commands > MAX_COMMANDS:
                        raise ValueError("Delta command limit exceeded")
                    if kind == 1:
                        stream.write(b"\x01" + struct.pack(">QQ", value, length))
                        copied += length
                    else:
                        assert isinstance(value, bytes)
                        stream.write(b"\x02" + struct.pack(">Q", len(value)))
                        stream.write(value)
                        literal += len(value)
                stream.write(b"\x00")
        generation_seconds = time.perf_counter() - started
        if temporary.stat().st_size > MAX_PATCH_BYTES:
            raise PatchTooLargeError("Generated delta exceeds client size limit")
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
            rebuilt = Path(output.name)
        started = time.perf_counter()
        reconstruct_patch(base, temporary, rebuilt)
        apply_seconds = time.perf_counter() - started
        if rebuilt.stat().st_size != target_size or rebuilt.read_bytes() != target_bytes:
            raise ValueError("Generated delta failed exact target verification")
        os.replace(temporary, destination)
        temporary = None
        return {
            "fromSha256": base_hash,
            "fromSize": base_size,
            "file": destination.name,
            "size": destination.stat().st_size,
            "sha256": sha256_file(destination),
            "targetSha256": target_hash,
            "targetSize": target_size,
            "copyBytes": copied,
            "literalBytes": literal,
            "commands": commands,
            "generationSeconds": round(generation_seconds, 4),
            "applySeconds": round(apply_seconds, 4),
        }
    finally:
        for path in (temporary, rebuilt):
            if path is not None:
                path.unlink(missing_ok=True)


def reconstruct_patch(base: Path, patch: Path, destination: Path) -> None:
    """Strict reference decoder, also used to verify every generated release."""
    base_size = _apk_size(base)
    if not 0 < patch.stat().st_size <= MAX_PATCH_BYTES:
        raise ValueError("Delta size outside supported limits")
    temporary = None
    try:
        with gzip.open(patch, "rb") as stream, base.open("rb") as source:
            if _read_exact(stream, 8) != MAGIC:
                raise ValueError("Unsupported delta format")
            expected_base, target_size = _u64(stream), _u64(stream)
            base_hash, target_hash = _read_exact(stream, 32), _read_exact(stream, 32)
            if expected_base != base_size or bytes.fromhex(sha256_file(base)) != base_hash:
                raise ValueError("Installed APK does not match delta base")
            if not 0 < target_size <= MAX_APK_BYTES:
                raise ValueError("Delta target size outside supported limits")
            with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
                temporary = Path(output.name)
                digest = hashlib.sha256()
                written = count = 0
                while True:
                    kind = _read_exact(stream, 1)[0]
                    if kind == 0:
                        break
                    count += 1
                    if count > MAX_COMMANDS:
                        raise ValueError("Delta command limit exceeded")
                    if kind == 1:
                        offset, length = _u64(stream), _u64(stream)
                        if offset > base_size or length > base_size - offset:
                            raise ValueError("Delta COPY exceeds base bounds")
                        source.seek(offset)
                        payload = source
                    elif kind == 2:
                        length = _u64(stream)
                        payload = stream
                    else:
                        raise ValueError("Unsupported delta command")
                    if length == 0 or length > target_size - written:
                        raise ValueError("Delta command exceeds target bounds")
                    remaining = length
                    while remaining:
                        block = _read_exact(payload, min(remaining, BUFFER_BYTES))
                        output.write(block)
                        digest.update(block)
                        written += len(block)
                        remaining -= len(block)
                if stream.read(1):
                    raise ValueError("Trailing data after delta END")
                if written != target_size or digest.digest() != target_hash:
                    raise ValueError("Reconstructed APK does not match target")
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _version(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError("Release version must have three numeric components")
    return tuple(int(part) for part in value.split("."))


def _apk_version_codes(metadata_path: Path, version: str, target_abis: set[str]) -> dict[str, int]:
    """Read the APK's actual version code, which split builds can change per ABI."""
    metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig"))
    if not isinstance(metadata, dict) or metadata.get("applicationId") != PACKAGE_NAME:
        raise ValueError("APK metadata applicationId does not match Kivo")
    artifact_type = metadata.get("artifactType")
    if not isinstance(artifact_type, dict) or artifact_type.get("type") != "APK":
        raise ValueError("APK metadata does not describe APK artifacts")
    elements = metadata.get("elements")
    if not isinstance(elements, list) or not elements:
        raise ValueError("APK metadata has no output elements")
    codes: dict[str, int] = {}
    for element in elements:
        if not isinstance(element, dict) or element.get("versionName") != version:
            raise ValueError("APK metadata versionName does not match release")
        filters = element.get("filters")
        if not isinstance(filters, list) or len(filters) != 1:
            raise ValueError("APK metadata must describe one ABI filter per APK")
        abi_filter = filters[0]
        if not isinstance(abi_filter, dict) or abi_filter.get("filterType") != "ABI":
            raise ValueError("APK metadata is missing an ABI filter")
        abi = abi_filter.get("value")
        if abi not in ABIS or abi in codes:
            raise ValueError("APK metadata has an unsupported or duplicate ABI")
        code = element.get("versionCode")
        if type(code) is not int or not 0 < code <= 2_147_483_647:
            raise ValueError("APK metadata versionCode must be a positive Android integer")
        codes[abi] = code
    if set(codes) != target_abis:
        raise ValueError("APK metadata ABI set does not match target APKs")
    return codes


def generate_release(
    base_dir: Path, target_dir: Path, output_dir: Path, version: str, version_code: int,
    apk_metadata: Path,
) -> dict:
    target_version = _version(version)
    if version_code <= 0:
        raise ValueError("Version code must be positive")
    output_dir.mkdir(parents=True, exist_ok=True)
    target_abis = {abi for abi in ABIS if (target_dir / f"kivo-v{version}-{abi}.apk").is_file()}
    if not target_abis:
        raise ValueError("No target APKs found for this release version")
    apk_codes = _apk_version_codes(apk_metadata, version, target_abis)
    artifacts = []
    report = []
    for abi in ABIS:
        target = target_dir / f"kivo-v{version}-{abi}.apk"
        if not target.is_file():
            continue
        artifact = {
            "abi": abi,
            "apk": target.name,
            "size": _apk_size(target),
            "sha256": sha256_file(target),
            "versionCode": apk_codes[abi],
            "patches": [],
        }
        bases: dict[tuple[int, ...], Path] = {}
        if base_dir.exists():
            for candidate in sorted(base_dir.rglob("*.apk")):
                match = APK_NAME.fullmatch(candidate.name)
                if not match or match[2] != abi:
                    continue
                parsed = _version(match[1])
                if parsed >= target_version:
                    continue
                if parsed in bases:
                    raise ValueError(f"Duplicate base APK for {match[1]} / {abi}")
                bases[parsed] = candidate
        for base_version in sorted(bases, reverse=True)[:2]:
            base = bases[base_version]
            from_version = ".".join(str(part) for part in base_version)
            patch = output_dir / f"kivo-v{version}-{abi}-from-v{from_version}.kdelta"
            try:
                result = generate_patch(base, target, patch)
            except PatchTooLargeError:
                report.append({"abi": abi, "fromVersion": from_version, "published": False, "reason": "patch exceeds client size limit"})
                continue
            worthwhile = result["size"] < artifact["size"] * PATCH_MAX_RATIO
            report.append({"abi": abi, "fromVersion": from_version,
                           "targetVersionCode": artifact["versionCode"], **result, "published": worthwhile})
            if worthwhile:
                artifact["patches"].append(
                    {key: result[key] for key in ("fromSha256", "fromSize", "file", "size", "sha256")}
                )
            else:
                patch.unlink()
        artifacts.append(artifact)
    manifest = {
        "schema": 1,
        "package": PACKAGE_NAME,
        "version": version,
        "versionCode": version_code,
        "artifacts": artifacts,
    }
    (output_dir / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": MANIFEST_NAME, "measurements": report}, indent=2))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    generate = commands.add_parser("generate", help="Create release manifest and useful verified deltas")
    for option in ("base-dir", "target-dir", "output-dir"):
        generate.add_argument("--" + option, type=Path, required=True)
    generate.add_argument("--version", required=True)
    generate.add_argument("--version-code", type=int, required=True)
    generate.add_argument("--apk-metadata", type=Path, required=True,
                          help="AGP output-metadata.json from the same split APK build")
    apply = commands.add_parser("apply", help="Reconstruct and verify an APK for local validation")
    for option in ("base", "patch", "output"):
        apply.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    if args.command == "generate":
        generate_release(args.base_dir, args.target_dir, args.output_dir, args.version,
                         args.version_code, args.apk_metadata)
    else:
        reconstruct_patch(args.base, args.patch, args.output)


if __name__ == "__main__":
    main()
