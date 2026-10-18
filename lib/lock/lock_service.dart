// Ustawienia blokady: PIN, wzór, biometria. Kod zapisywany wyłącznie jako skrót z solą.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LockMode { none, pin, pattern, biometric }

LockMode _modeFrom(String? s) => LockMode.values.firstWhere((m) => m.name == s, orElse: () => LockMode.none);

String lockModeLabel(LockMode m) => switch (m) {
      LockMode.none => 'Brak',
      LockMode.pin => 'Kod PIN',
      LockMode.pattern => 'Wzór',
      LockMode.biometric => 'Tylko odcisk / twarz',
    };

class LockService {
  LockService._();
  static final LockService I = LockService._();

  static const _kMode = 'lock_mode';
  static const _kHash = 'lock_hash';
  static const _kSalt = 'lock_salt';
  static const _kLen = 'lock_len';
  static const _kBio = 'lock_bio';
  static const _kTimeout = 'lock_timeout_s';
  static const _kFails = 'lock_fails';
  static const _kUntil = 'lock_until_ms';
  static const _kLegacy = 'lock'; // wersja 1.0: tylko biometria

  static const timeouts = <int, String>{0: 'Od razu', 60: 'Po 1 minucie', 300: 'Po 5 minutach', 900: 'Po 15 minutach'};

  LockMode mode = LockMode.none;

  /// true, gdy aplikacja chwilowo oddaje ekran (biometria, wybór pliku) – nie blokuj po powrocie.
  bool external = false;

  Future<T> whileExternal<T>(Future<T> Function() f) async {
    external = true;
    try {
      return await f();
    } finally {
      // zdarzenie "resumed" przychodzi chwilę po zamknięciu okna systemowego
      Future.delayed(const Duration(milliseconds: 800), () => external = false);
    }
  }
  bool bio = false;
  int codeLength = 0;
  int timeoutS = 60;

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<void> load() async {
    try {
      final p = await _p;
      if (!p.containsKey(_kMode) && (p.getBool(_kLegacy) ?? false)) {
        await p.setString(_kMode, LockMode.biometric.name);
      }
      mode = _modeFrom(p.getString(_kMode));
      bio = p.getBool(_kBio) ?? false;
      codeLength = p.getInt(_kLen) ?? 0;
      timeoutS = p.getInt(_kTimeout) ?? 60;
      if ((mode == LockMode.pin || mode == LockMode.pattern) && (p.getString(_kHash) ?? '').isEmpty) {
        mode = LockMode.none; // uszkodzone ustawienia – nie blokuj na zawsze
      }
    } catch (_) {
      mode = LockMode.none;
    }
  }

  bool get enabled => mode != LockMode.none;
  bool get usesSecret => mode == LockMode.pin || mode == LockMode.pattern;
  bool get bioAllowed => mode == LockMode.biometric || (usesSecret && bio);

  static String _hash(String secret, String salt) {
    List<int> h = utf8.encode('$salt|$secret');
    for (var i = 0; i < 20000; i++) {
      h = sha256.convert([...h, ...utf8.encode(salt)]).bytes;
    }
    return base64Encode(h);
  }

  static String _newSalt() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// Ustawia PIN lub wzór (secret = cyfry albo kolejne punkty "0-4-8").
  Future<void> setSecret(LockMode m, String secret, int length) async {
    final p = await _p;
    final salt = _newSalt();
    await p.setString(_kSalt, salt);
    await p.setString(_kHash, _hash(secret, salt));
    await p.setInt(_kLen, length);
    await p.setString(_kMode, m.name);
    await p.remove(_kFails);
    await p.remove(_kUntil);
    mode = m;
    codeLength = length;
  }

  Future<void> setBiometricOnly() async {
    final p = await _p;
    await p.setString(_kMode, LockMode.biometric.name);
    await p.remove(_kHash);
    await p.remove(_kSalt);
    mode = LockMode.biometric;
  }

  Future<void> disable() async {
    final p = await _p;
    await p.setString(_kMode, LockMode.none.name);
    await p.remove(_kHash);
    await p.remove(_kSalt);
    await p.remove(_kLen);
    await p.remove(_kFails);
    await p.remove(_kUntil);
    await p.remove(_kLegacy);
    mode = LockMode.none;
  }

  Future<void> setBio(bool v) async {
    await (await _p).setBool(_kBio, v);
    bio = v;
  }

  Future<void> setTimeout(int s) async {
    await (await _p).setInt(_kTimeout, s);
    timeoutS = s;
  }

  /// Ile jeszcze trzeba czekać po zbyt wielu błędnych próbach.
  Future<Duration> cooldown() async {
    final until = (await _p).getInt(_kUntil) ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  Future<int> failures() async => (await _p).getInt(_kFails) ?? 0;

  /// Sprawdza kod. Po 5 błędach blokuje próby: 30 s, potem coraz dłużej (do 15 min).
  Future<bool> verify(String secret) async {
    final p = await _p;
    if ((await cooldown()) > Duration.zero) return false;
    final salt = p.getString(_kSalt) ?? '';
    final ok = salt.isNotEmpty && _hash(secret, salt) == p.getString(_kHash);
    if (ok) {
      await p.remove(_kFails);
      await p.remove(_kUntil);
      return true;
    }
    final fails = (p.getInt(_kFails) ?? 0) + 1;
    await p.setInt(_kFails, fails);
    if (fails >= 5) {
      final step = fails - 5; // 0,1,2…
      final secs = min(30 * pow(2, step).toInt(), 900);
      await p.setInt(_kUntil, DateTime.now().millisecondsSinceEpoch + secs * 1000);
    }
    return false;
  }

  /// Odcisk palca / twarz. [allowDeviceCredential] dopuszcza też blokadę ekranu telefonu.
  Future<bool> biometric({String reason = 'Odblokuj Portfel', bool allowDeviceCredential = false}) async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return mode == LockMode.biometric && !allowDeviceCredential;
      return await whileExternal(() => auth.authenticate(
            localizedReason: reason,
            options: AuthenticationOptions(biometricOnly: !allowDeviceCredential, stickyAuth: true),
          ));
    } catch (_) {
      return false;
    }
  }

  Future<bool> canUseBiometrics() async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }
}
