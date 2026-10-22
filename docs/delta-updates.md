# Partial updates from GitHub

Kivo can download a patch for its exact installed APK instead of downloading
another full APK. It reconstructs the signed release file byte for byte; it
does not replace running Dart code or sign anything on the phone. Android still
asks the user to install the update.

The first release containing this updater requires a full download. Patches are
an optional optimization: unknown bases, split installs, unavailable metadata,
or failed patch preparation use the full APK. A failed full download remains a
normal retryable update failure.

## Release artifacts

The existing three signed APKs stay available. After building them, the release
workflow downloads the last two available stable releases into isolated build
directories and runs `scripts/update_delta.py generate`. Partial failed base
downloads are excluded. Each generated patch is applied locally and compared
byte for byte with its signed target before publication.

`kivo-update-v1.json` lists the package, Android version name and version code,
then one artifact per ABI. Each artifact includes the full APK filename, size,
SHA-256, actual Android version code, and zero or more patches identified by base
APK size and SHA-256. The actual codes come from AGP's output-metadata.json;
Flutter's split-per-ABI codes differ from the pubspec build number.
Patches are published only when smaller than 80% of the full APK. Missing
usable bases still produce a full-APK verification manifest.

The manifest and patches are additional GitHub Release assets. Existing Kivo
versions ignore them and continue to download APKs normally. The rate-limit
fallback infers the manifest URL from the release tag; a legacy release without
that asset continues to work.

## Format

`KIVODLT1` is a gzip-compressed stream. All integers are unsigned 64-bit big
endian values; the Android parser rejects values outside signed Long bounds.

| Field | Encoding |
| --- | --- |
| Magic | 8 bytes: `KIVODLT1` |
| Base and target sizes | Two u64 values |
| Base and target SHA-256 | Two raw 32-byte digests |
| END | Opcode 0; decoded EOF must follow |
| COPY | Opcode 1, base offset u64, length u64 |
| DATA | Opcode 2, length u64, literal bytes |

The generator reuses identical raw ZIP entry ranges, including payloads whose
local headers or alignment have changed. Changed ranges become gzip-compressed
literals. Neither ZIP contents nor APK signatures are recreated or recompressed.

Both parsers bound APK size to 512 MiB, compressed patch size to 256 MiB and
command count to one million. Commands cannot read outside the base or write
past the target. Zero lengths, truncated input, wrong hashes, unknown opcodes,
missing END and trailing decoded data are rejected. Android copies in 64 KiB
buffers and performs hashing, reconstruction and verification off the UI thread.

## Download and recovery

`UpdateDownloads` owns native job metadata and preparation. DownloadManager owns
the actual transfer, so downloads survive closing Kivo. The original download
id remains a stable handle even if patch failure starts a full download. Native
metadata is persisted atomically and Dart can recover a handle that was not yet
written to its settings.

Completed downloads with metadata enter `preparing`, not `ready`. Preparation
copies and verifies the downloaded bytes, checks the installed base, rebuilds
into a private temporary file, and verifies the exact target size and digest.
The package, increasing version code, version name and verified signer set must
match the release and installed app before the result becomes installable.
The verified file is published atomically and checked again before installation.

Android's archive lookup is requested with GET_SIGNATURES and, on API28+, also
GET_SIGNING_CERTIFICATES. Both are intentional: Android9 needs the former to
trigger verified certificate collection. AOSP routes this lookup through full
APK signature verification, rather than its unsafe certificate-extraction path:
[Android9](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-9.0.0_r61/core/java/android/content/pm/PackageManager.java#4811),
[Android15 parser](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/core/java/com/android/internal/pm/pkg/parsing/ParsingPackageUtils.java#636).
Signing-key rotation is not supported by either manifest-backed update path.

After process death, incomplete preparation restarts from the retained download.
Cancelling removes the job's downloads, temporary files and prepared APK. A
successful installation is recognized by the app version on the next launch,
which cleans up the old update. Hiding the dialog keeps the job available.

## Measured result

Signed ARM64 releases v1.31.0 to v1.31.1:

| Item | Bytes |
| --- | ---: |
| Full target APK | 35,060,000 |
| Patch | 3,786,270 |
| Saved download | 89.2% |

The reconstructed target SHA-256 was
`daefbb9336eb26043c05817a97084e1df3415ebb1ba66679264deab8713c9a6b`.
Generation took 1.47s and reference reconstruction 0.23s in Python on the Windows
development machine. These are not Android performance measurements or a promise
of the same savings in later releases.

## Checks

Run the Python codec tests with `python -B -m unittest discover -s scripts -p
test_update_delta.py`, Flutter update tests under `test/core/update`,
`test/platform` and `test/ui/update`, and Android update unit tests with
`:app:testDebugUnitTest`. Build an APK to check the native bridge as well as Dart.
Physical installation, process death and OEM signature behavior require Android
runtime verification in addition to these tests.
