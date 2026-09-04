import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../../platform/biometric_auth_provider.dart';
import '../../platform/interfaces/biometric_auth.dart';
import '../../vault/vault_providers.dart';
import 'pin_pad.dart';

/// Auth barrier. Shows [child] only once unlocked. First run: set a PIN (twice).
/// Returning run: biometric auto-prompt (if enabled+available) with PIN fallback.
/// Re-locks when this route is left or the app is backgrounded.
class VaultGate extends ConsumerStatefulWidget {
  final Widget child;
  const VaultGate({super.key, required this.child});
  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate> with WidgetsBindingObserver {
  String? _error;
  String? _firstPin; // set-PIN flow: holds the first entry
  bool _biometricTried = false;
  // True from the moment _maybeBiometric() commits to calling
  // bio.authenticate(...) until that call resolves (success, failure, or any
  // early-return path taken after it was set). Independent of _biometricTried
  // so it also protects against a `resumed` re-attempt firing a second,
  // concurrent authenticate() call while the OS biometric sheet from the
  // first attempt is still up (stickyAuth delivers inactive/paused/resumed
  // around the sheet while the original await is still pending).
  bool _biometricInFlight = false;
  // Set only when the app is paused/inactivated WHILE a biometric attempt is
  // still in flight (i.e. the OS sheet may have been yanked away mid-attempt
  // by real backgrounding, not resolved). This is the sole trigger for the
  // resume handler below re-attempting biometric. A resume that follows an
  // attempt that already resolved — including the user tapping Cancel on
  // the sheet, which local_auth reports as a plain `false` indistinguishable
  // from a failed attempt — leaves this false, so it does nothing: no
  // re-prompt, no loop. See didChangeAppLifecycleState and _maybeBiometric.
  bool _biometricInterrupted = false;
  // While true, a biometric attempt is either about to start or in flight,
  // so the OS biometric sheet owns the screen and PinPad stays hidden
  // underneath a simple placeholder. False shows PinPad immediately (no
  // biometric applicable, or the attempt already resolved/was bailed out of).
  // Computed synchronously here (not just in the post-frame callback) so a
  // biometric-eligible gate never paints PinPad on the very first frame.
  late bool _showPinPad = !_willAttemptBiometric();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fresh mount = locked (each openVault pushes a new gate, so re-entry
      // always re-authenticates). Reset in a post-frame, NOT in build/dispose:
      // writing provider state during build throws, and ref in dispose is a
      // known footgun in this codebase.
      ref.read(vaultUnlockedProvider.notifier).state = false;
      if (mounted) setState(() => _showPinPad = !_willAttemptBiometric());
      _maybeBiometric();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ref.read(vaultUnlockedProvider.notifier).state = false;
      // Only remember this as a genuine interruption when a biometric
      // attempt was actually in flight. If it isn't — e.g. the previous
      // attempt already resolved because the user tapped Cancel or the
      // fingerprint just wasn't recognized — this pause is not a reason to
      // retry biometric on the next resume.
      if (_biometricInFlight) _biometricInterrupted = true;
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      final unlocked = ref.read(vaultUnlockedProvider);
      final auth = ref.read(vaultAuthProvider);
      // Only reachable when the prior attempt never got a chance to
      // resolve (app was backgrounded mid-prompt, e.g. OS killed the
      // sheet): give it another shot at biometric instead of silently
      // downgrading to PIN-only. Deliberately does NOT fire for a resume
      // that follows an attempt the user already resolved by cancelling —
      // that must land on PinPad and stay there, not re-summon the sheet.
      // NOTE: if a biometric attempt is still in flight (e.g. this resume
      // is the OS biometric sheet resolving while the original
      // authenticate() await from _maybeBiometric() hasn't returned yet),
      // _biometricInFlight guards _maybeBiometric() below from starting a
      // second, concurrent authenticate() call.
      if (!unlocked && auth.isConfigured && _biometricInterrupted) {
        _biometricInterrupted = false;
        _biometricTried = false;
        setState(() => _showPinPad = !_willAttemptBiometric());
        _maybeBiometric();
      }
    }
  }

  /// Whether a biometric attempt will actually be kicked off right now
  /// (i.e. PIN is configured, biometric is enabled in settings, and the
  /// platform reports it as available). Does not consult [_biometricTried].
  bool _willAttemptBiometric() {
    final auth = ref.read(vaultAuthProvider);
    if (!auth.isConfigured) return false; // set-PIN flow instead
    return ref.read(settingsProvider).vaultBiometricEnabled;
  }

  Future<void> _maybeBiometric() async {
    // A genuine concurrent-re-entry guard: independent of _biometricTried
    // because `resumed` deliberately resets _biometricTried to false so a
    // fresh background/foreground cycle gets another shot at biometric — but
    // if we're resuming WHILE the original authenticate() call is still
    // pending (on some devices the OS biometric sheet itself causes an
    // inactive/paused/resumed dance while it's showing — nothing to do with
    // local_auth's own stickyAuth option, which this app leaves off; see
    // local_auth_biometric.dart), that pending call must be left alone, not
    // raced.
    if (_biometricInFlight) return;
    if (_biometricTried) return;
    _biometricTried = true;
    final auth = ref.read(vaultAuthProvider);
    if (!auth.isConfigured) return; // set-PIN flow instead
    final enabled = ref.read(settingsProvider).vaultBiometricEnabled;
    if (!enabled) return;
    final bio = ref.read(biometricAuthProvider);
    if (!await bio.isAvailable()) {
      if (mounted) setState(() => _showPinPad = true);
      return;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    final messages = BiometricAuthMessages(
      reason: l10n.vaultUnlockReason,
      signInTitle: l10n.vaultUnlockBiometricSignInTitle,
      biometricHint: l10n.vaultUnlockBiometricHint,
      biometricNotRecognized: l10n.vaultUnlockBiometricNotRecognized,
      biometricSuccess: l10n.vaultUnlockBiometricSuccessMessage,
      cancelButton: l10n.commonCancel,
      biometricRequiredTitle: l10n.vaultUnlockBiometricRequiredTitle,
      goToSettingsButton: l10n.vaultUnlockGoToSettingsButton,
      goToSettingsDescription: l10n.vaultUnlockGoToSettingsDescription,
      deviceCredentialsRequiredTitle:
          l10n.vaultUnlockDeviceCredentialsRequiredTitle,
      deviceCredentialsSetupDescription:
          l10n.vaultUnlockDeviceCredentialsSetupDescription,
    );
    _biometricInFlight = true;
    try {
      final ok = await bio.authenticate(messages);
      if (ok && mounted) {
        ref.read(vaultUnlockedProvider.notifier).state = true;
      } else if (mounted) {
        setState(() => _showPinPad = true);
      }
    } finally {
      _biometricInFlight = false;
    }
  }

  void _bailToPinPad() {
    setState(() => _showPinPad = true);
  }

  void _submitPin(String pin) {
    final auth = ref.read(vaultAuthProvider);
    if (auth.verify(pin)) {
      ref.read(vaultUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = context.l10n.vaultPinIncorrectError);
    }
  }

  Future<void> _submitSetPin(String pin) async {
    if (_firstPin == null) {
      setState(() { _firstPin = pin; _error = null; });
      return;
    }
    if (_firstPin != pin) {
      setState(() { _firstPin = null; _error = context.l10n.vaultPinMismatchError; });
      return;
    }
    await ref.read(vaultAuthProvider).setPin(pin);
    if (mounted) ref.read(vaultUnlockedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(vaultUnlockedProvider);
    if (unlocked) return widget.child;

    final auth = ref.watch(vaultAuthProvider);
    final configuring = !auth.isConfigured;
    final l10n = context.l10n;
    final title = configuring
        ? (_firstPin == null ? l10n.vaultCreatePinTitle : l10n.vaultRepeatPinTitle)
        : l10n.vaultEnterPinTitle;

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: Center(
        child: _showPinPad
            ? PinPad(
                title: title,
                error: _error,
                onComplete: configuring ? _submitSetPin : _submitPin,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 64, color: cs.secondary),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _bailToPinPad,
                    child: Text(l10n.vaultUsePinAction),
                  ),
                ],
              ),
      ),
    );
  }
}
