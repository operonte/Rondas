import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones locales para alertas críticas. Complementa (no reemplaza) el
/// modal a pantalla completa: si el guardia tiene la app en segundo plano, el
/// modal no se ve y la alerta pasaba desapercibida.
///
/// Son locales, no push: llegan solo con la app viva (en foreground o
/// background). Para avisar con la app cerrada del todo hace falta FCM.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationDetails _alertChannel = AndroidNotificationDetails(
    'rondas_alerts',
    'Alertas de ronda',
    channelDescription: 'Alertas críticas: verificación aleatoria, batería baja y pánico.',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
  );

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        // Icono de status bar: Android tiñe a blanco solido e ignora el color,
        // así que necesita una silueta con alfa, no el ic_launcher a color
        // (se veía como un bloque blanco sin forma).
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_rondas'),
        ),
      );
      // Android 13+ exige permiso explícito de notificaciones.
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      // Sin notificaciones la app sigue siendo usable (queda el modal).
    }
  }

  static Future<void> showAlert({required String title, required String body}) async {
    if (!_ready || kIsWeb) return;
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _alertChannel),
      );
    } catch (_) {}
  }

  /// Aviso de pérdida de conexión: prioridad baja, no debe competir con las
  /// alertas de ronda ni sonar como emergencia.
  static Future<void> showConnectivityNotice({required String title, required String body}) async {
    if (!_ready || kIsWeb) return;
    try {
      await _plugin.show(
        id: 9001, // fijo: un aviso de conexión reemplaza al anterior
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'rondas_connectivity',
            'Estado de conexión',
            channelDescription: 'Avisos de pérdida y recuperación de conexión.',
            importance: Importance.low,
            priority: Priority.low,
          ),
        ),
      );
    } catch (_) {}
  }
}
