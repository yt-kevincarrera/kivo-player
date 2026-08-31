/// Every operation that can fail in a way the user sees.
///
/// Adding a value here without adding a catalog entry below fails
/// `kivo_failure_test.dart` — that is deliberate.
enum KivoOp {
  mediaAccess,
  libraryScan,
  thumbnail,
  delete,
  rename,
  share,
  vaultHide,
  vaultRestore,
  vaultPurge,
  openVideo,
  frameCapture,
  subtitleLoad,
  updateCheck,
  updateInstall,

  /// Anything that reached the UI without being classified. Having a code for
  /// "we don't know" is the point: an uncoded error is the hole this closes.
  unknown,
}

/// Code and copy for each operation, grouped by domain:
/// 1xx access · 2xx library · 3xx file ops · 4xx vault · 5xx playback · 6xx updates
///
/// Codes are APPEND-ONLY. Users quote them and bug reports refer to them, so a
/// shipped code keeps its meaning forever — never renumber, never reuse.
const kivoErrorCatalog = <KivoOp, ({String code, String message})>{
  KivoOp.mediaAccess:
      (code: 'KV-101', message: 'No pudimos acceder a tus videos'),
  KivoOp.libraryScan:
      (code: 'KV-201', message: 'No pudimos leer tu biblioteca'),
  KivoOp.thumbnail:
      (code: 'KV-202', message: 'No pudimos generar la miniatura'),
  KivoOp.delete: (code: 'KV-301', message: 'No pudimos borrar el video'),
  KivoOp.rename: (code: 'KV-302', message: 'No pudimos renombrar el video'),
  KivoOp.share: (code: 'KV-303', message: 'No pudimos compartir el video'),
  KivoOp.vaultHide: (code: 'KV-401', message: 'No pudimos ocultar el video'),
  KivoOp.vaultRestore:
      (code: 'KV-402', message: 'No pudimos restaurar el video'),
  KivoOp.vaultPurge:
      (code: 'KV-403', message: 'No pudimos borrar el video definitivamente'),
  KivoOp.openVideo: (code: 'KV-501', message: 'No pudimos abrir el video'),
  KivoOp.subtitleLoad:
      (code: 'KV-502', message: 'No pudimos cargar el subtítulo'),
  KivoOp.frameCapture:
      (code: 'KV-503', message: 'No pudimos guardar la captura'),
  KivoOp.updateCheck:
      (code: 'KV-601', message: 'No pudimos comprobar si hay actualizaciones'),
  KivoOp.updateInstall:
      (code: 'KV-602', message: 'No pudimos instalar la actualización'),
  KivoOp.unknown:
      (code: 'KV-999', message: 'Algo no salió como esperábamos'),
};

/// A failure the user is allowed to see: a friendly [message], a quotable
/// [code], and the technical [detail] kept separate so it only shows where it
/// was asked for.
class KivoFailure implements Exception {
  const KivoFailure(this.op, this.cause);

  final KivoOp op;

  /// The original exception (or a descriptive string). Never rendered by
  /// [toString] — only reachable through [detail].
  final Object cause;

  String get code => kivoErrorCatalog[op]!.code;
  String get message => kivoErrorCatalog[op]!.message;
  String get detail => cause.toString();

  /// Deliberately omits [cause]. A screen that interpolates `'$failure'` — the
  /// exact mistake that put a SQLite error in front of a user — gets the
  /// friendly text, not the stack.
  @override
  String toString() => '$code $message';
}
