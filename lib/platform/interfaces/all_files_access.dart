/// "All files access" (Android MANAGE_EXTERNAL_STORAGE). When granted, the app
/// can delete/rename media without the per-operation system consent dialog.
abstract class AllFilesAccess {
  /// Whether the permission is granted right now.
  Future<bool> isGranted();

  /// Opens the special settings screen to grant it. Resolves (with the
  /// resulting granted state) when the user returns.
  Future<bool> request();
}

/// Whether to show the one-time "grant all-files-access" offer: only when the
/// permission isn't granted and we haven't offered it before.
bool shouldOfferAllFilesAccess(bool granted, bool offered) => !granted && !offered;
