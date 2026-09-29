part of 'track_picker.dart';

String _familyLabel(AppLocalizations l10n, EncodingFamily f) => switch (f) {
      EncodingFamily.unicode => l10n.encodingUnicode,
      EncodingFamily.western => l10n.encodingWestern,
      EncodingFamily.central => l10n.encodingCentral,
      EncodingFamily.cyrillic => l10n.encodingCyrillic,
      EncodingFamily.greek => l10n.encodingGreek,
      EncodingFamily.turkish => l10n.encodingTurkish,
      EncodingFamily.hebrew => l10n.encodingHebrew,
      EncodingFamily.arabic => l10n.encodingArabic,
      EncodingFamily.baltic => l10n.encodingBaltic,
      EncodingFamily.vietnamese => l10n.encodingVietnamese,
      EncodingFamily.thai => l10n.encodingThai,
      EncodingFamily.chineseSimplified => l10n.encodingChineseSimplified,
      EncodingFamily.chineseTraditional => l10n.encodingChineseTraditional,
      EncodingFamily.japanese => l10n.encodingJapanese,
      EncodingFamily.korean => l10n.encodingKorean,
    };

/// "Cirílico" for any spelling of a Cyrillic charset; the raw name for one
/// outside every family.
String encodingDisplayName(AppLocalizations l10n, String charset) {
  final family = familyOf(charset);
  return family == null ? charset : _familyLabel(l10n, family);
}

/// The encoding card's second line: what the file is being read as.
String encodingSummary(AppLocalizations l10n, ActiveExternalSubtitle a) {
  final enc = a.encoding;
  if (!a.detected && enc != null) return encodingDisplayName(l10n, enc);
  if (enc == null) return l10n.playerTracksEncodingAuto;
  return l10n.playerTracksEncodingAutoDetected(encodingDisplayName(l10n, enc));
}

/// Opens on top of the track picker, so back returns to it.
Future<void> showSubtitleEncodingSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _EncodingSheet(),
  );
}

class _EncodingSheet extends ConsumerStatefulWidget {
  const _EncodingSheet();

  @override
  ConsumerState<_EncodingSheet> createState() => _EncodingSheetState();
}

class _EncodingSheetState extends ConsumerState<_EncodingSheet> {
  bool _more = false;
  Future<List<String>>? _available;

  void _pick(String? charset) {
    Navigator.of(context).pop();
    ref.read(subtitleLoaderProvider).reloadWithEncoding(charset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final active = ref.watch(activeExternalSubtitleProvider);
    // What the user chose for this video; null = automatic.
    final chosen = (active != null && !active.detected) ? active.encoding : null;
    final detected =
        (active != null && active.detected) ? active.encoding : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: _Grabber()),
              _SheetHeader(title: l10n.playerTracksEncodingSheetTitle),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    _TrackCard(
                      icon: Icons.auto_fix_high_rounded,
                      label: l10n.playerTracksEncodingAuto,
                      sublabel: detected == null
                          ? l10n.playerTracksEncodingAutoHint
                          : l10n.playerTracksEncodingAutoDetected(
                              encodingDisplayName(l10n, detected)),
                      active: chosen == null,
                      accent: accent,
                      onTap: () => _pick(null),
                    ),
                    for (final e in curatedSubtitleEncodings)
                      _TrackCard(
                        icon: Icons.translate_rounded,
                        label: _familyLabel(l10n, e.family),
                        sublabel: e.charset,
                        active: sameCharset(chosen, e.charset),
                        accent: accent,
                        onTap: () => _pick(e.charset),
                      ),
                    if (!_more)
                      _TrackCard(
                        icon: Icons.expand_more_rounded,
                        label: l10n.playerTracksEncodingMore,
                        sublabel: '',
                        active: false,
                        accent: accent,
                        onTap: () => setState(() {
                          _more = true;
                          _available ??= ref
                              .read(subtitleTranscoderProvider)
                              .availableEncodings();
                        }),
                      )
                    else
                      FutureBuilder<List<String>>(
                        future: _available,
                        builder: (context, snap) {
                          final extra = extraEncodings(snap.data ?? const []);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final c in extra)
                                _TrackCard(
                                  icon: Icons.text_fields_rounded,
                                  label: c,
                                  sublabel: encodingDisplayName(l10n, c) == c
                                      ? ''
                                      : encodingDisplayName(l10n, c),
                                  active: sameCharset(chosen, c),
                                  accent: accent,
                                  onTap: () => _pick(c),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
