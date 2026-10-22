"""Release-generator contract and malformed-input regression tests.

Run with: python -m unittest discover -s scripts -p 'test_update_delta.py'
"""

import contextlib
import gzip
import hashlib
import io
import json
from pathlib import Path
import random
import struct
import tempfile
import unittest
from unittest import mock
import zipfile

import update_delta as delta


class DeltaTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.base = self.root / "base.apk"
        self.base.write_bytes(b"installed APK bytes")
        self.patch = self.root / "patch.kdelta"
        self.output = self.root / "output.apk"

    def tearDown(self):
        self.directory.cleanup()

    def program(self, body, target=b"installed APK bytes", **header):
        contents = (
            header.get("magic", delta.MAGIC)
            + struct.pack(">QQ", header.get("base_size", self.base.stat().st_size), header.get("target_size", len(target)))
            + header.get("base_hash", bytes.fromhex(delta.sha256_file(self.base)))
            + header.get("target_hash", hashlib.sha256(target).digest())
            + body
        )
        self.patch.write_bytes(gzip.compress(contents, mtime=0))

    @staticmethod
    def copy(offset, length):
        return b"\x01" + struct.pack(">QQ", offset, length)

    @staticmethod
    def data(value):
        return b"\x02" + struct.pack(">Q", len(value)) + value

    def reject(self):
        self.output.write_bytes(b"existing verified download")
        with self.assertRaises((ValueError, EOFError, gzip.BadGzipFile)):
            delta.reconstruct_patch(self.base, self.patch, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing verified download")
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["base.apk", "output.apk", "patch.kdelta"])

    def test_streaming_copy_and_data_reconstruct_in_target_order(self):
        target = b"APK!installed"
        self.program(self.copy(10, 3) + self.data(b"!") + self.copy(0, 9) + b"\x00", target)
        delta.reconstruct_patch(self.base, self.patch, self.output)
        self.assertEqual(self.output.read_bytes(), target)

    def test_wrong_base_same_size_is_rejected_before_output(self):
        self.program(self.copy(0, self.base.stat().st_size) + b"\x00")
        self.base.write_bytes(b"different APK bytes")
        self.reject()

    def test_wrong_base_size_is_rejected(self):
        self.program(b"\x00", base_size=1)
        self.reject()

    def test_unknown_format_is_rejected(self):
        self.program(b"\x00", magic=b"KIVODLT2")
        self.reject()

    def test_wrong_target_hash_is_rejected(self):
        self.program(self.copy(0, self.base.stat().st_size) + b"\x00", target_hash=b"0" * 32)
        self.reject()

    def test_missing_end_is_rejected(self):
        self.program(self.copy(0, self.base.stat().st_size))
        self.reject()

    def test_trailing_program_after_end_is_rejected(self):
        self.program(self.copy(0, self.base.stat().st_size) + b"\x00" + self.data(b"injected"))
        self.reject()

    def test_extra_gzip_member_after_end_is_rejected(self):
        self.program(self.copy(0, self.base.stat().st_size) + b"\x00")
        with self.patch.open("ab") as stream:
            stream.write(gzip.compress(b"injected", mtime=0))
        self.reject()

    def test_gzip_checksum_is_verified(self):
        self.program(self.copy(0, self.base.stat().st_size) + b"\x00")
        contents = bytearray(self.patch.read_bytes())
        contents[-8] ^= 1
        self.patch.write_bytes(contents)
        self.reject()

    def test_truncated_header_is_rejected(self):
        self.patch.write_bytes(gzip.compress(delta.MAGIC + b"\x00", mtime=0))
        self.reject()

    def test_truncated_literal_is_rejected(self):
        self.program(b"\x02" + struct.pack(">Q", 10) + b"123")
        self.reject()

    def test_zero_length_commands_are_rejected(self):
        for command in (self.copy(0, 0), self.data(b"")):
            with self.subTest(command=command):
                self.program(command + b"\x00")
                self.reject()

    def test_copy_bounds_and_unsigned_overflow_values_are_rejected(self):
        for offset, length in ((20, 1), (18, 2), ((1 << 64) - 1, 1), (0, (1 << 64) - 1)):
            with self.subTest(offset=offset, length=length):
                self.program(self.copy(offset, length) + b"\x00")
                self.reject()

    def test_output_overflow_is_rejected(self):
        self.program(self.data(b"too long") + b"\x00", target=b"x")
        self.reject()

    def test_early_end_is_rejected(self):
        self.program(b"\x00")
        self.reject()

    def test_unknown_command_is_rejected(self):
        self.program(b"\x03\x00")
        self.reject()

    def test_command_count_limit_is_enforced(self):
        self.program(self.data(b"x") + self.data(b"y") + b"\x00", target=b"xy")
        with mock.patch.object(delta, "MAX_COMMANDS", 1):
            self.reject()

    def test_target_size_limit_is_enforced(self):
        for size in (0, delta.MAX_APK_BYTES + 1, (1 << 64) - 1):
            with self.subTest(size=size):
                self.program(b"\x00", target_size=size)
                self.reject()

    def apk(self, path, shared, changed, extra=b""):
        with zipfile.ZipFile(path, "w") as archive:
            info = zipfile.ZipInfo("lib/arm64-v8a/libflutter.so")
            info.extra = extra
            archive.writestr(info, shared, compress_type=zipfile.ZIP_STORED)
            archive.writestr("assets/changed", changed, compress_type=zipfile.ZIP_DEFLATED)
        with path.open("ab") as output:
            output.write(b"opaque target trailer\x00\xff")

    def metadata(self, codes, version="2.0.0"):
        path = self.root / "output-metadata.json"
        path.write_text(json.dumps({
            "version": 3,
            "artifactType": {"type": "APK", "kind": "Directory"},
            "applicationId": delta.PACKAGE_NAME,
            "elements": [
                {"filters": [{"filterType": "ABI", "value": abi}],
                 "versionCode": code, "versionName": version,
                 "outputFile": f"app-{abi}-release.apk"}
                for abi, code in codes.items()
            ],
        }), encoding="utf-8")
        return path

    def test_generator_preserves_raw_zip_bytes_alignment_and_trailer(self):
        shared = random.Random(1234).randbytes(128 * 1024)
        self.apk(self.base, shared, b"old" * 1000)
        target = self.root / "target.apk"
        # Valid ZIP extra field changes the local alignment header only.
        self.apk(target, shared, b"new" * 1001, extra=b"\xfe\xca\x04\x00pad!")
        stats = delta.generate_patch(self.base, target, self.patch)
        delta.reconstruct_patch(self.base, self.patch, self.output)
        self.assertEqual(self.output.read_bytes(), target.read_bytes())
        self.assertGreaterEqual(stats["copyBytes"], len(shared))
        self.assertLess(stats["size"], target.stat().st_size // 10)
        first = self.patch.read_bytes()
        delta.generate_patch(self.base, target, self.patch)
        self.assertEqual(self.patch.read_bytes(), first)

    def test_release_selects_two_newest_bases_and_has_full_apk_fallback(self):
        bases, targets, outputs = (self.root / name for name in ("bases", "targets", "outputs"))
        for directory in (bases, targets):
            directory.mkdir()
        shared = random.Random(1234).randbytes(128 * 1024)
        for version in ("1.0.0", "1.0.1", "1.1.0", "3.0.0"):
            self.apk(bases / f"kivo-v{version}-arm64-v8a.apk", shared, version.encode())
        self.apk(targets / "kivo-v2.0.0-arm64-v8a.apk", shared, b"new version")
        self.apk(targets / "kivo-v2.0.0-x86_64.apk", b"no base", b"new version")
        metadata = self.metadata({"arm64-v8a": 4042, "x86_64": 5042})
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = delta.generate_release(bases, targets, outputs, "2.0.0", 42, metadata)
        self.assertEqual(manifest["package"], "dev.selector.kivo_player")
        self.assertEqual(manifest["versionCode"], 42)
        arm, x86 = manifest["artifacts"]
        self.assertEqual(arm["versionCode"], 4042)
        self.assertEqual(x86["versionCode"], 5042)
        self.assertEqual([item["file"] for item in arm["patches"]], [
            "kivo-v2.0.0-arm64-v8a-from-v1.1.0.kdelta",
            "kivo-v2.0.0-arm64-v8a-from-v1.0.1.kdelta",
        ])
        self.assertEqual(x86["patches"], [])
        self.assertEqual(x86["sha256"], delta.sha256_file(targets / x86["apk"]))
        self.assertTrue((outputs / delta.MANIFEST_NAME).is_file())

    def test_not_worthwhile_patch_is_omitted_and_deleted(self):
        bases, targets, outputs = (self.root / name for name in ("bases", "targets", "outputs"))
        for directory in (bases, targets):
            directory.mkdir()
        self.apk(bases / "kivo-v1.0.0-arm64-v8a.apk", b"old", b"old")
        self.apk(targets / "kivo-v2.0.0-arm64-v8a.apk", random.Random(7).randbytes(8192), b"new")
        metadata = self.metadata({"arm64-v8a": 4042})
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = delta.generate_release(bases, targets, outputs, "2.0.0", 42, metadata)
        self.assertEqual(manifest["artifacts"][0]["patches"], [])
        self.assertEqual(list(outputs.glob("*.kdelta")), [])

    def test_patch_over_client_limit_keeps_full_apk_in_manifest(self):
        bases, targets, outputs = (self.root / name for name in ("bases", "targets", "outputs"))
        for directory in (bases, targets):
            directory.mkdir()
        shared = random.Random(1234).randbytes(128 * 1024)
        self.apk(bases / "kivo-v1.0.0-arm64-v8a.apk", shared, b"old")
        self.apk(targets / "kivo-v2.0.0-arm64-v8a.apk", shared, b"new")
        metadata = self.metadata({"arm64-v8a": 4042})
        with mock.patch.object(delta, "MAX_PATCH_BYTES", 4), contextlib.redirect_stdout(io.StringIO()):
            manifest = delta.generate_release(bases, targets, outputs, "2.0.0", 42, metadata)
        artifact = manifest["artifacts"][0]
        self.assertEqual(artifact["patches"], [])
        self.assertEqual(artifact["sha256"], delta.sha256_file(targets / artifact["apk"]))
        self.assertEqual(list(outputs.glob("*.kdelta")), [])

    def test_metadata_version_codes_are_read_without_assuming_abi_offsets(self):
        metadata = self.metadata({"arm64-v8a": 17, "armeabi-v7a": 998, "x86_64": 12345})
        self.assertEqual(delta._apk_version_codes(metadata, "2.0.0", set(delta.ABIS)), {
            "arm64-v8a": 17, "armeabi-v7a": 998, "x86_64": 12345,
        })

    def test_metadata_rejects_wrong_package_version_abi_filters_and_codes(self):
        metadata = self.metadata({"arm64-v8a": 4058})
        valid = json.loads(metadata.read_text())
        mutations = [
            lambda data: data.update(applicationId="other.application"),
            lambda data: data.update(artifactType={"type": "AAB"}),
            lambda data: data.update(elements=[]),
            lambda data: data["elements"][0].update(versionName="1.9.0"),
            lambda data: data["elements"][0].update(filters=[]),
            lambda data: data["elements"][0].update(filters=[{"filterType": "DENSITY", "value": "arm64-v8a"}]),
            lambda data: data["elements"][0].update(filters=[{"filterType": "ABI", "value": "unknown"}]),
            lambda data: data["elements"].append(data["elements"][0].copy()),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                invalid = json.loads(json.dumps(valid))
                mutate(invalid)
                metadata.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaises(ValueError):
                    delta._apk_version_codes(metadata, "2.0.0", {"arm64-v8a"})
        for code in (0, -1, True, "4058", None, 2_147_483_648):
            with self.subTest(code=code):
                invalid = json.loads(json.dumps(valid))
                invalid["elements"][0]["versionCode"] = code
                metadata.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaises(ValueError):
                    delta._apk_version_codes(metadata, "2.0.0", {"arm64-v8a"})

    def test_metadata_requires_exact_abi_set_from_current_target_apks(self):
        metadata = self.metadata({"arm64-v8a": 4058})
        with self.assertRaises(ValueError):
            delta._apk_version_codes(metadata, "2.0.0", {"arm64-v8a", "x86_64"})
        metadata = self.metadata({"arm64-v8a": 4058, "x86_64": 5058})
        with self.assertRaises(ValueError):
            delta._apk_version_codes(metadata, "2.0.0", {"arm64-v8a"})

    def test_generate_cli_requires_metadata_from_the_same_build(self):
        arguments = ["update_delta.py", "generate", "--base-dir", str(self.root),
                     "--target-dir", str(self.root), "--output-dir", str(self.root),
                     "--version", "2.0.0", "--version-code", "42"]
        with mock.patch("sys.argv", arguments), contextlib.redirect_stderr(io.StringIO()) as error:
            with self.assertRaises(SystemExit) as exited:
                delta.main()
        self.assertEqual(exited.exception.code, 2)
        self.assertIn("--apk-metadata", error.getvalue())


if __name__ == "__main__":
    unittest.main()
