import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import '../security/lock.dart';
import '../main.dart';
import '../notify.dart';
import 'alerts_screen.dart';
import 'format.dart';
import 'security_screen.dart';
import 'tax_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LockConfig? lock;

  @override
  void initState() {
    super.initState();
    _loadLock();
    _loadNotify();
  }

  Future<void> _export() async {
    final now = DateTime.now();
    final name = 'portfel-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    try {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Zapisz kopię Portfela', fileName: name, bytes: app.exportBytes());
      if (path != null) toast(context, 'Zapisano kopię');
    } catch (e) {
      toast(context, 'Nie udało się zapisać kopii: $e');
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) {
      toast(context, 'Nie udało się odczytać pliku');
      return;
    }
    try {
      final s = await app.importBytes(bytes);
      toast(context,
          'Wczytano: ${s.txCount} transakcji, ${s.depCount} lokat, ${s.cashCount} gotówki, ${s.propCount} nieruchomości (nowe: ${s.added}, zaktualizowane: ${s.updated})');
    } on FormatException catch (e) {
      toast(context, e.message);
    } catch (_) {
      toast(context, 'To nie jest plik kopii Portfela (.json)');
    }
  }

  Future<void> _loadLock() async {
    final c = await Lock.load();
    if (mounted) setState(() => lock = c);
  }

  NotifySettings? _notify;

  Future<void> _loadNotify() async {
    final n = await NotifySettings.load();
    if (mounted) setState(() => _notify = n);
  }

  Future<void> _setNotify(bool? on, int? days) async {
    final n = _notify ?? NotifySettings();
    if (on != null) n.deposits = on;
    if (days != null) n.daysBefore = days;
    await n.save();
    setState(() => _notify = n);
    if (n.deposits) await Notify.requestPermission();
    final c = await Notify.scheduleDeposits(app.deposits);
    if (mounted && n.deposits) toast(context, c == 0 ? 'Brak trwających lokat z datą końca' : 'Zaplanowano przypomnień: $c');
  }

  String get _lockLabel => switch (lock?.method) {
        LockMethod.pin => 'PIN${lock!.biometric ? ' + biometria' : ''}',
        LockMethod.pattern => 'Wzór${lock!.biometric ? ' + biometria' : ''}',
        LockMethod.device => 'Blokada ekranu telefonu',
        _ => 'Wyłączone',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = app.rates;
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(children: [
        const _Header('Dane'),
        const KoofrBackupTile(),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Importuj kopię'),
          subtitle: const Text('Plik .json z Portfela. Wpisy o tym samym id zostaną zaktualizowane, nowe dodane.'),
          onTap: _import,
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Zapisz kopię'),
          subtitle: Text('${app.txs.length} transakcji, ${app.deposits.length} lokat, ${app.cash.length} gotówki, ${app.properties.length} nieruchomości'),
          onTap: _export,
        ),
        const _Header('Przypomnienia i podatki'),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Alerty cenowe'),
          subtitle: Text(app.alerts.where((a) => a.active).isEmpty ? 'Powiadomienie, gdy kurs osiągnie ustawiony poziom' : 'Aktywne: ${app.alerts.where((a) => a.active).length}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.event_available_outlined),
          title: const Text('Przypomnienia o końcu lokat'),
          subtitle: Text(_notify == null ? '' : '${_notify!.daysBefore} ${_notify!.daysBefore == 1 ? 'dzień' : 'dni'} przed końcem i w dniu zakończenia, o 9:00'),
          value: _notify?.deposits ?? true,
          onChanged: (v) => _setNotify(v, null),
        ),
        if (_notify?.deposits ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
            child: Wrap(spacing: 8, children: [
              for (final d in const [1, 3, 7, 14])
                ChoiceChip(label: Text('$d dni'), selected: _notify!.daysBefore == d, onSelected: (_) => _setNotify(null, d)),
            ]),
          ),
        ListTile(
          leading: const Icon(Icons.request_quote_outlined),
          title: const Text('Zestawienie roczne'),
          subtitle: const Text('Wynik sprzedaży walut i kruszców (FIFO), zasada pół roku dla złota i srebra, odsetki z lokat'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxScreen())),
        ),
        const _Header('Prywatność'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Logowanie do aplikacji'),
          subtitle: Text(_lockLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
            _loadLock();
          },
        ),
        const _Header('Kursy'),
        ListTile(
          leading: const Icon(Icons.currency_exchange),
          title: Text(r.asOf != null ? 'Notowanie z ${dateFmt(r.asOf)}' : 'Brak notowań'),
          subtitle: Text(r.source),
          trailing: app.refreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: () async {
            await app.refreshRates(force: true);
            if (mounted) setState(() {});
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Text(
            'Waluty: kursy średnie NBP (tabela A). Złoto: cena NBP za 1 g. Srebro: cena spot w USD (gold-api.com) przeliczona po kursie NBP. '
            'Wycena nie uwzględnia spreadu kantoru ani marży monet. Lokaty: odsetki narosłe liczone liniowo, po 19% podatku.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );
}
