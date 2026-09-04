import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)` — `context.l10n.someKey`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
