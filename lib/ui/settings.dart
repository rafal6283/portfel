import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool lock = false;

  @override
  void initState() {
    super.initState();
    LockGate.isEnabled().then((v) {
      if (mounted) setState(() => lock = v);
    });
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
      toast(context, 'Wczytano ${s.txCount} transakcji i ${s.depCount} lokat (nowe: ${s.added}, zaktualizowane: ${s.updated})');
    } on FormatException catch (e) {
      toast(context, e.message);
    } catch (_) {
      toast(context, 'To nie jest plik kopii Portfela (.json)');
    }
  }

  Future<void> _toggleLock(bool v) async {
    if (v && !await LockGate.authenticate()) {
      toast(context, 'Nie udało się potwierdzić tożsamości');
      return;
    }
    await LockGate.setEnabled(v);
    setState(() => lock = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = app.rates;
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(children: [
        const _Header('Dane'),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Importuj kopię'),
          subtitle: const Text('Plik .json z Portfela. Wpisy o tym samym id zostaną zaktualizowane, nowe dodane.'),
          onTap: _import,
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Zapisz kopię'),
          subtitle: Text('${app.txs.length} transakcji, ${app.deposits.length} lokat'),
          onTap: _export,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Blokada odciskiem / twarzą'),
          subtitle: const Text('Pyta przy starcie i po 2 minutach w tle'),
          value: lock,
          onChanged: _toggleLock,
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
