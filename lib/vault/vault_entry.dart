/// A video that has been moved into the Vault. Persisted in Hive because once
/// the file leaves MediaStore we no longer get its metadata from a scan.
class VaultEntry {
  final String id;                    // original MediaStore id — stable key
  final String privatePath;           // absolute path inside the vault dir
  final String displayName;           // file name incl. extension — resume key + label
  final String originalRelativePath;  // MediaStore RELATIVE_PATH for restore, '' if unknown
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  final int width;
  final int height;

  const VaultEntry({
    required this.id,
    required this.privatePath,
    required this.displayName,
    required this.originalRelativePath,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.dateAddedMs = 0,
    this.width = 0,
    this.height = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'privatePath': privatePath,
        'displayName': displayName,
        'originalRelativePath': originalRelativePath,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'dateAddedMs': dateAddedMs,
        'width': width,
        'height': height,
      };

  factory VaultEntry.fromMap(Map<String, dynamic> m) => VaultEntry(
        id: m['id'] as String,
        privatePath: m['privatePath'] as String,
        displayName: m['displayName'] as String,
        originalRelativePath: (m['originalRelativePath'] as String?) ?? '',
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
      );
}
