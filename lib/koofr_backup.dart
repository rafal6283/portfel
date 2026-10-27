import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'main.dart' show app;

/// Kopia Portfela na rodzinnym Koofr (ten sam plik JSON co „Zapisz kopię”, zaszyfrowany).
class PortfelBackup extends BackupAdapter {
  @override
  String get appId => 'portfel';
  @override
  String get appName => 'Portfel';
  @override
  String get contentNote => 'W kopii są transakcje, lokaty, gotówka, nieruchomości i ręczne kursy.';

  @override
  Future<BackupContent> export() async => BackupContent(app.exportBytes());

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    try {
      await app.replaceFromBytes(r.data);
    } on FormatException catch (e) {
      throw KoofrException(e.message);
    }
  }
}
