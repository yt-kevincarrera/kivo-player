import '../../core/errors/kivo_failure.dart';
import '../../l10n/generated/app_localizations.dart';

/// Localized counterpart to [kivoErrorCatalog]'s Spanish `message` — one ARB
/// key per [KivoOp], read by the adapters that show a failure to the user
/// ([showFailureSnackBar]/[showFailureSnackBarOn], [FailureView]).
///
/// The catalog itself is NOT translated: its `message` stays the log/raw
/// text (project rule — KV-nnn copy is translated where it is shown, never
/// in the catalog), and its `code` is never translated at all.
String failureMessage(AppLocalizations l10n, KivoOp op) => switch (op) {
      KivoOp.mediaAccess => l10n.errorMediaAccess,
      KivoOp.libraryScan => l10n.errorLibraryScan,
      KivoOp.thumbnail => l10n.errorThumbnail,
      KivoOp.delete => l10n.errorDelete,
      KivoOp.rename => l10n.errorRename,
      KivoOp.share => l10n.errorShare,
      KivoOp.vaultHide => l10n.errorVaultHide,
      KivoOp.vaultRestore => l10n.errorVaultRestore,
      KivoOp.vaultPurge => l10n.errorVaultPurge,
      KivoOp.openVideo => l10n.errorOpenVideo,
      KivoOp.subtitleLoad => l10n.errorSubtitleLoad,
      KivoOp.frameCapture => l10n.errorFrameCapture,
      KivoOp.updateCheck => l10n.errorUpdateCheck,
      KivoOp.updateInstall => l10n.errorUpdateInstall,
      KivoOp.unknown => l10n.errorUnknown,
    };
