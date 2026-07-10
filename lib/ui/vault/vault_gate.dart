import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/biometric_auth_provider.dart';
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
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      final unlocked = ref.read(vaultUnlockedProvider);
      final auth = ref.read(vaultAuthProvider);
      if (!unlocked && auth.isConfigured) {
        // User backgrounded mid-vault and came back: don't silently
        // downgrade to PIN-only, give them another shot at biometric.
        // NOTE: if a biometric attempt is still in flight (e.g. this resume
        // is the OS biometric sheet resolving while the original
        // authenticate() await from _maybeBiometric() hasn't returned yet),
        // _biometricInFlight guards _maybeBiometric() below from starting a
        // second, concurrent authenticate() call.
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
    // pending (stickyAuth's inactive/paused/resumed dance around the OS
    // biometric sheet), that pending call must be left alone, not raced.
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
    _biometricInFlight = true;
    try {
      final ok = await bio.authenticate('Desbloquea el Vault');
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
      setState(() => _error = 'PIN incorrecto');
    }
  }

  Future<void> _submitSetPin(String pin) async {
    if (_firstPin == null) {
      setState(() { _firstPin = pin; _error = null; });
      return;
    }
    if (_firstPin != pin) {
      setState(() { _firstPin = null; _error = 'Los PIN no coinciden'; });
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
    final title = configuring
        ? (_firstPin == null ? 'Crea un PIN para el Vault' : 'Repite el PIN')
        : 'Introduce tu PIN';

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
                    child: const Text('Usar PIN'),
                  ),
                ],
              ),
      ),
    );
  }
}
