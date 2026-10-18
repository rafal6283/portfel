import 'dart:async';

import 'package:flutter/material.dart';

import 'lock_service.dart';
import 'pads.dart';

/// Ekran odblokowania. [onUnlocked] wywołane po poprawnym kodzie, wzorze lub biometrii.
class UnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockScreen({super.key, required this.onUnlocked});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final lock = LockService.I;
  String message = '';
  Duration wait = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkCooldown();
    if (lock.bioAllowed) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkCooldown() async {
    final w = await lock.cooldown();
    if (!mounted) return;
    setState(() => wait = w);
    _timer?.cancel();
    if (w > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        final left = await lock.cooldown();
        if (!mounted) return;
        setState(() => wait = left);
        if (left == Duration.zero) {
          _timer?.cancel();
          setState(() => message = '');
        }
      });
    }
  }

  Future<void> _bio() async {
    if (await lock.biometric()) widget.onUnlocked();
  }

  Future<void> _try(String secret) async {
    if (await lock.verify(secret)) {
      widget.onUnlocked();
      return;
    }
    final fails = await lock.failures();
    setState(() => message = lock.mode == LockMode.pin ? 'Nieprawidłowy PIN' : 'Nieprawidłowy wzór');
    if (fails >= 5) {
      await _checkCooldown();
    } else if (fails >= 3) {
      setState(() => message += ' · zostały ${5 - fails} próby przed przerwą');
    }
  }

  Future<void> _forgot() async {
    final ok = await lock.biometric(
        reason: 'Potwierdź blokadą ekranu telefonu, aby ustawić nowy kod', allowDeviceCredential: true);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nie udało się potwierdzić tożsamości. Bez blokady ekranu w telefonie nie da się zresetować kodu.')));
      }
      return;
    }
    await lock.disable();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blokada wyłączona. Ustaw nowy kod w Ustawieniach.')));
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = wait > Duration.zero;
    final title = switch (lock.mode) {
      LockMode.pin => 'Wpisz PIN',
      LockMode.pattern => 'Narysuj wzór',
      _ => 'Portfel jest zablokowany',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 40, color: cs.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: Text(
                  locked ? 'Za dużo prób. Spróbuj za ${wait.inSeconds + 1} s' : message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error),
                ),
              ),
              const SizedBox(height: 8),
              if (lock.mode == LockMode.pin)
                PinPad(
                  length: lock.codeLength >= 4 ? lock.codeLength : 4,
                  enabled: !locked,
                  onSubmit: _try,
                  leftKey: lock.bioAllowed
                      ? IconButton(onPressed: _bio, icon: const Icon(Icons.fingerprint, size: 30), tooltip: 'Odcisk palca / twarz')
                      : null,
                )
              else if (lock.mode == LockMode.pattern)
                PatternPad(enabled: !locked, minPoints: 1, onSubmit: (p) => _try(p.join('-'))),
              const SizedBox(height: 16),
              if (lock.bioAllowed && lock.mode != LockMode.pin)
                FilledButton.tonalIcon(onPressed: _bio, icon: const Icon(Icons.fingerprint), label: const Text('Odcisk palca / twarz')),
              if (lock.usesSecret)
                TextButton(onPressed: _forgot, child: Text(lock.mode == LockMode.pin ? 'Nie pamiętasz PIN-u?' : 'Nie pamiętasz wzoru?')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ustawianie PIN-u albo wzoru (dwa razy to samo). Zwraca true po zapisaniu.
class SetSecretScreen extends StatefulWidget {
  final LockMode mode;
  const SetSecretScreen({super.key, required this.mode});
  @override
  State<SetSecretScreen> createState() => _SetSecretScreenState();
}

class _SetSecretScreenState extends State<SetSecretScreen> {
  String? first;
  String error = '';
  Key padKey = UniqueKey();
  int len = 4;

  bool get pin => widget.mode == LockMode.pin;

  Future<void> _entered(String v, int length) async {
    if (first == null) {
      setState(() {
        first = v;
        error = '';
        padKey = UniqueKey();
      });
      return;
    }
    if (first != v) {
      setState(() {
        first = null;
        error = pin ? 'PIN-y się różnią. Zacznij od nowa.' : 'Wzory się różnią. Zacznij od nowa.';
        padKey = UniqueKey();
      });
      return;
    }
    try {
      await LockService.I.setSecret(widget.mode, v, length);
    } catch (e) {
      setState(() {
        first = null;
        error = 'Nie udało się zapisać: $e';
        padKey = UniqueKey();
      });
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = first == null
        ? (pin ? 'Wpisz nowy PIN' : 'Narysuj nowy wzór (co najmniej 4 punkty)')
        : (pin ? 'Wpisz PIN jeszcze raz' : 'Narysuj wzór jeszcze raz');
    return Scaffold(
      appBar: AppBar(title: Text(pin ? 'Ustaw PIN' : 'Ustaw wzór')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(step, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            SizedBox(height: 22, child: Text(error, style: TextStyle(color: cs.error))),
            const SizedBox(height: 8),
            if (pin && first == null)
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 4, label: Text('4 cyfry')),
                  ButtonSegment(value: 6, label: Text('6 cyfr')),
                ],
                selected: {len},
                onSelectionChanged: (v) => setState(() {
                  len = v.first;
                  padKey = UniqueKey();
                }),
              ),
            const SizedBox(height: 16),
            if (pin)
              PinPad(key: padKey, length: len, onSubmit: (v) => _entered(v, v.length))
            else
              PatternPad(key: padKey, onSubmit: (p) => _entered(p.join('-'), p.length)),
          ]),
        ),
      ),
    );
  }
}
