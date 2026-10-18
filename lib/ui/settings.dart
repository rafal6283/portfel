import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../lock/lock_screens.dart';
import '../lock/lock_service.dart';
import '../main.dart';
import 'format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final lock = LockService.I;
  bool canBio = false;

  @override
  void initState() {
    super.initState();
    lock.canUseBiometrics().then((v) {
      if (mounted) setState(() => canBio = v);
    });
  }

  Future<void> _export() async {
    final now = DateTime.now();
    final name = 'portfel-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    try {
      final path = await lock.whileExternal(
          () => FilePicker.platform.saveFile(dialogTitle: 'Zapisz kopię Portfela', fileName: name, bytes: app.exportBytes()));
      if (path != null) toast(context, 'Zapisano kopię');
    } catch (e) {
      toast(context, 'Nie udało się zapisać kopii: $e');
    }
  }

  Future<void> _import() async {
    final res = await lock.whileExternal(() => FilePicker.platform.pickFiles(type: FileType.any, withData: true));
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

  Future<void> _chooseMode() async {
    final picked = await showModalBottomSheet<LockMode>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in [LockMode.none, LockMode.pin, LockMode.pattern, if (canBio) LockMode.biometric])
            ListTile(
              leading: Icon(switch (m) {
                LockMode.none => Icons.lock_open,
                LockMode.pin => Icons.pin_outlined,
                LockMode.pattern => Icons.pattern,
                LockMode.biometric => Icons.fingerprint,
              }),
              title: Text(lockModeLabel(m)),
              trailing: lock.mode == m ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, m),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    switch (picked) {
      case LockMode.none:
        if (lock.enabled && !await confirm(context, 'Wyłączyć blokadę?', 'Każdy, kto weźmie telefon, zobaczy Twój portfel.', ok: 'Wyłącz')) return;
        await lock.disable();
        toast(context, 'Blokada wyłączona');
      case LockMode.pin:
      case LockMode.pattern:
        final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SetSecretScreen(mode: picked)));
        if (ok == true) {
          toast(context, picked == LockMode.pin ? 'PIN ustawiony' : 'Wzór ustawiony');
          if (canBio && !lock.bio) {
            final use = await confirm(context, 'Odcisk palca / twarz?', 'Odblokowywać też biometrią? PIN lub wzór zostaje jako zapasowy.', ok: 'Tak');
            if (use && await lock.biometric(reason: 'Potwierdź, aby włączyć odblokowanie biometrią')) await lock.setBio(true);
          }
        }
      case LockMode.biometric:
        if (!await lock.biometric(reason: 'Potwierdź, aby włączyć blokadę')) {
          toast(context, 'Nie udało się potwierdzić tożsamości');
          return;
        }
        await lock.setBiometricOnly();
        toast(context, 'Blokada włączona');
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleBio(bool v) async {
    if (v && !await lock.biometric(reason: 'Potwierdź, aby włączyć odblokowanie biometrią')) {
      toast(context, 'Nie udało się potwierdzić tożsamości');
      return;
    }
    await lock.setBio(v);
    setState(() {});
  }

  Future<void> _chooseTimeout() async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Blokuj po wyjściu z aplikacji'),
        children: [
          for (final e in LockService.timeouts.entries)
            ListTile(
              title: Text(e.value),
              trailing: lock.timeoutS == e.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, e.key),
            ),
        ],
      ),
    );
    if (v != null) {
      await lock.setTimeout(v);
      setState(() {});
    }
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
        const _Header('Blokada'),
        ListTile(
          leading: Icon(lock.enabled ? Icons.lock_outline : Icons.lock_open),
          title: const Text('Blokada aplikacji'),
          subtitle: Text(lockModeLabel(lock.mode)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _chooseMode,
        ),
        if (lock.usesSecret && canBio)
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Odblokowanie odciskiem / twarzą'),
            subtitle: Text(lock.mode == LockMode.pin ? 'PIN zostaje jako zapasowy' : 'Wzór zostaje jako zapasowy'),
            value: lock.bio,
            onChanged: _toggleBio,
          ),
        if (lock.enabled)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Blokuj po wyjściu z aplikacji'),
            subtitle: Text(LockService.timeouts[lock.timeoutS] ?? '${lock.timeoutS} s'),
            onTap: _chooseTimeout,
          ),
        if (lock.usesSecret)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Po 5 błędnych próbach trzeba odczekać 30 s (potem coraz dłużej). '
              'Zapomniany kod można zresetować blokadą ekranu telefonu.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
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
