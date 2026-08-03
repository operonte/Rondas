import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'offline_service.dart';
import 'session_service.dart';

class AlertService {
  RealtimeChannel? _channel;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Battery _battery = Battery();
  bool _lowBatteryTriggered = false;
  StreamSubscription<BatteryState>? _batterySubscription;

  void initRealtimeAlerts(Function(Map<String, dynamic>) onAlertTriggered) {
    _channel = SupabaseConfig.client
        .channel('public:alerts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          callback: (payload) {
            final record = payload.newRecord;
            if (record['status'] == 'pending') {
              playAlertSound();
              NotificationService.showAlert(
                title: '¡ALERTA DE RONDA!',
                body: record['type'] == 'panic'
                    ? 'Alerta de pánico activada. Abre la app y confirma.'
                    : 'Verificación solicitada por central. Abre la app y confirma.',
              );
              onAlertTriggered(record);
            }
          },
        )
        .subscribe();

    _startBatteryMonitor(onAlertTriggered);
  }

  void playAlertSound() async {
    try {
      // Asset local: si esto dependiera de una URL externa, una alerta de
      // pánico sin internet no sonaría justo cuando más importa.
      await _audioPlayer.play(AssetSource('sounds/alarm.wav'));
    } catch (_) {}
  }

  void stopAlertSound() async {
    await _audioPlayer.stop();
  }

  void _startBatteryMonitor(Function(Map<String, dynamic>) onAlertTriggered) async {
    _battery.batteryLevel.then((level) {
      _evaluateBatteryLevel(level, onAlertTriggered);
    });

    _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
      final level = await _battery.batteryLevel;
      _evaluateBatteryLevel(level, onAlertTriggered);
    });
  }

  void _evaluateBatteryLevel(int level, Function(Map<String, dynamic>) onAlertTriggered) {
    if (level < 15 && !_lowBatteryTriggered) {
      _lowBatteryTriggered = true;
      final alertData = {
        'id': 'battery_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'low_battery',
        'status': 'pending',
        'triggered_at': DateTime.now().toIso8601String(),
      };
      playAlertSound();
      NotificationService.showAlert(
        title: 'Batería crítica',
        body: 'Batería al $level%. Conecta el cargador para no perder el registro de la ronda.',
      );
      onAlertTriggered(alertData);
    } else if (level >= 15) {
      _lowBatteryTriggered = false;
    }
  }

  Future<void> respondAlert(String alertId, String? photoUrl) async {
    stopAlertSound();

    // Las alertas locales (batería baja) no existen en la base: su id no es un
    // uuid, así que no hay nada que confirmar del lado del servidor.
    final isRemoteAlert = !alertId.startsWith('battery_');
    if (isRemoteAlert && await OfflineService.checkConnectivityStatus()) {
      final token = await SessionService.getToken();
      if (token != null) {
        try {
          await SupabaseConfig.client.rpc('acknowledge_alert', params: {
            'p_token': token,
            'p_alert_id': alertId,
            'p_photo_url': photoUrl,
          });
        } catch (_) {}
      }
    }

    final userId = await AuthService.getCurrentUserId();
    await OfflineService.saveSystemLog(
      'alert_response',
      'Alerta $alertId atendida y confirmada por el guardia.',
      userId: userId,
    );
  }

  void dispose() {
    _batterySubscription?.cancel();
    if (_channel != null) {
      SupabaseConfig.client.removeChannel(_channel!);
    }
    _audioPlayer.dispose();
  }
}

final alertService = AlertService();
