// Powiadomienia: koniec lokat (zaplanowane) i alerty cenowe (od razu).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'alerts.dart';
import 'models.dart';
import 'ui/format.dart';

class NotifySettings {
  bool deposits;
  int daysBefore;
  NotifySettings({this.deposits = true, this.daysBefore = 3});

  static Future<NotifySettings> load() async {
    final p = await SharedPreferences.getInstance();
    return NotifySettings(deposits: p.getBool('dep_remind') ?? true, daysBefore: p.getInt('dep_days') ?? 3);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('dep_remind', deposits);
    await p.setInt('dep_days', daysBefore);
  }
}

class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _depBase = 1000; // identyfikatory przypomnień o lokatach: 1000…1199

  static const _depDetails = NotificationDetails(
    android: AndroidNotificationDetails('lokaty', 'Koniec lokat', channelDescription: 'Przypomnienia o kończących się lokatach', importance: Importance.defaultImportance),
    iOS: DarwinNotificationDetails(),
  );
  static const _alertDetails = NotificationDetails(
    android: AndroidNotificationDetails('alerty', 'Alerty cenowe', channelDescription: 'Kurs waluty lub kruszcu osiągnął ustawiony poziom', importance: Importance.high),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      String name = 'Europe/Warsaw';
      try {
        name = await FlutterTimezone.getLocalTimezone();
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
      }
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('Powiadomienia niedostępne: $e');
    }
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    return false;
  }

  /// Planuje od nowa przypomnienia o lokatach (po każdej zmianie lokat).
  static Future<int> scheduleDeposits(List<Deposit> deposits) async {
    await init();
    if (!_ready) return 0;
    try {
      for (var i = 0; i < 200; i++) {
        await _plugin.cancel(_depBase + i);
      }
      final s = await NotifySettings.load();
      if (!s.deposits) return 0;
      final list = depositReminders(deposits, daysBefore: s.daysBefore).take(60).toList();
      for (var i = 0; i < list.length; i++) {
        final (when, title, body) = list[i];
        await _plugin.zonedSchedule(_depBase + i, title, body, tz.TZDateTime.from(when, tz.local), _depDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
      }
      return list.length;
    } catch (e) {
      debugPrint('Planowanie przypomnień nie powiodło się: $e');
      return 0;
    }
  }

  static Future<void> alerts(List<PriceAlert> fired) async {
    if (fired.isEmpty) return;
    await init();
    if (!_ready) return;
    for (final a in fired) {
      final unit = isMetal(a.asset) ? 'zł/g' : 'zł';
      await _plugin.show(
        2000 + a.id.hashCode.abs() % 1000,
        '${assetOf(a.asset).name}: ${a.above ? 'powyżej' : 'poniżej'} ${n2(a.price)} $unit',
        'Kurs ${rateFmt(a.asset, a.firedRate)} $unit (${a.asset}). Alert wyłączony – możesz ustawić nowy w Portfelu.',
        _alertDetails,
      );
    }
  }
}
