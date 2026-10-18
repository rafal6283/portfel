import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';
import 'ui/format.dart';
import 'ui/home.dart';

final AppState app = AppState();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PortfelApp());
}

class PortfelApp extends StatelessWidget {
  const PortfelApp({super.key});

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: Palette.seed, brightness: b);
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      appBarTheme: AppBarTheme(backgroundColor: cs.surface, scrolledUnderElevation: 1, centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portfel',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LockGate(child: HomeScreen()),
    );
  }
}

/// Opcjonalna blokada odciskiem palca / twarzą / kodem telefonu.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool('lock') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool('lock', v);

  static Future<bool> authenticate() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return true;
      return await auth.authenticate(localizedReason: 'Odblokuj Portfel');
    } catch (_) {
      return false;
    }
  }

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _checked = false;
  bool _locked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await app.load();
    final on = await LockGate.isEnabled();
    setState(() {
      _locked = on;
      _checked = true;
    });
    if (on) _unlock();
    app.refreshRates();
  }

  Future<void> _unlock() async {
    final ok = await LockGate.authenticate();
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    if (s == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      if (_pausedAt != null && DateTime.now().difference(_pausedAt!) > const Duration(minutes: 2) && await LockGate.isEnabled()) {
        setState(() => _locked = true);
        _unlock();
      }
      app.refreshRates();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_locked) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            const Text('Portfel jest zablokowany'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Odblokuj')),
          ]),
        ),
      );
    }
    return widget.child;
  }
}
