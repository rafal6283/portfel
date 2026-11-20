import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofr_backup_ui/testing.dart';
import 'package:portfel/koofr_backup.dart';
import 'package:portfel/main.dart' show app;
import 'package:portfel/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kopia na Koofr → nowy telefon (tylko kod odzyskiwania) → przywrócenie: transakcje wracają.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('portfel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => dir.path);
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null; // serwer WebDAV w pamięci potrzebuje prawdziwego HttpClient
  });

  test('przywrócenie kopii na czystym telefonie', () async {
    app.txs = [
      Tx(id: 't1', date: '2026-01-10', side: 'buy', asset: 'USD', qty: 100, total: 400, fee: 1),
      Tx(id: 't2', date: '2026-03-02', side: 'buy', asset: 'XAU', qty: 31.1, total: 12000, fee: 0, note: 'sztabka'),
    ];
    final restored = await kopiaAdapteraNaNowyTelefon(PortfelBackup());

    app.txs = [];
    await PortfelBackup().import(restored, (_) {});
    expect(app.txs.map((t) => t.id), unorderedEquals(['t1', 't2']));
    expect(app.txs.firstWhere((t) => t.id == 't2').note, 'sztabka');
    expect(app.txs.firstWhere((t) => t.id == 't1').total, 400);
  });
}
