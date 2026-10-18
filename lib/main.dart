import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'lock/lock_screens.dart';
import 'lock/lock_service.dart';
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
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
      home: const HomeScreen(),
    );
  }
}

/// Blokada aplikacji: PIN, wzór albo odcisk palca / twarz (Ustawienia → Blokada).
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final lock = LockService.I;
  bool _checked = false;
  bool _locked = false;
  bool _covered = false; // zasłona w podglądzie ostatnich aplikacji
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await Future.wait([app.load(), lock.load()]);
    setState(() {
      _locked = lock.enabled;
      _checked = true;
    });
    app.refreshRates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // okno odcisku palca, wybór pliku itp. też wyrzucają aplikację w tło – wtedy nie blokuj
    if (lock.external || _locked) {
      if (s == AppLifecycleState.resumed) _leftAt = null;
      return;
    }
    if (!lock.enabled) {
      if (s == AppLifecycleState.resumed) app.refreshRates();
      return;
    }
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.hidden) {
      if (!_covered) setState(() => _covered = true);
    }
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    }
    if (s == AppLifecycleState.resumed) {
      final away = _leftAt == null ? Duration.zero : DateTime.now().difference(_leftAt!);
      _leftAt = null;
      setState(() {
        _covered = false;
        if (!_locked && away.inSeconds >= lock.timeoutS && away > const Duration(seconds: 2)) _locked = true;
      });
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
    return Stack(children: [
      Offstage(offstage: !_checked || _locked, child: widget.child),
      if (!_checked) const Positioned.fill(child: Scaffold(body: Center(child: CircularProgressIndicator()))),
      if (_checked && _locked) Positioned.fill(child: UnlockScreen(onUnlocked: () => setState(() => _locked = false))),
      if (_covered && !_locked)
        Positioned.fill(
          child: ColoredBox(
            color: Palette.board,
            child: const Center(child: Icon(Icons.lock_outline, color: Palette.boardDim, size: 48)),
          ),
        ),
    ]);
  }
}
