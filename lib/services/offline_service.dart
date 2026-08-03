import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/supabase_config.dart';
import 'notification_service.dart';
import 'security_service.dart';
import 'session_service.dart';

class OfflineService {
  static const String _gpsBoxName = 'gps_queue';
  static const String _incidentBoxName = 'incidents_queue';
  static const String _logsBoxName = 'logs_queue';
  static const String _syncMetaBoxName = 'sync_meta';
  static const bool _useEncryption = true;
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(false);
  static final ValueNotifier<int> pendingSyncCount = ValueNotifier<int>(0);
  static final ValueNotifier<String> lastSyncLabel = ValueNotifier<String>('Nunca sincronizado');

  static Future<HiveAesCipher?> _getEncryptionCipher() async {
    if (!_useEncryption) return null;
    try {
      const keyMaterial = SupabaseConfig.supabaseAnonKey;
      if (keyMaterial.isEmpty) return null;
      final secretKey = SecurityService.deriveEncryptionKey(keyMaterial);
      return HiveAesCipher(secretKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> init() async {
    await Hive.initFlutter();
    final cipher = await _getEncryptionCipher();

    await Hive.openBox(_gpsBoxName, encryptionCipher: cipher);
    await Hive.openBox(_incidentBoxName, encryptionCipher: cipher);
    await Hive.openBox(_logsBoxName, encryptionCipher: cipher);
    await Hive.openBox(_syncMetaBoxName, encryptionCipher: cipher);

    final metaBox = Hive.box(_syncMetaBoxName);
    final storedLastSync = metaBox.get('last_sync_at') as String?;
    if (storedLastSync != null) {
      try {
        lastSyncLabel.value = _formatSyncLabel(DateTime.parse(storedLastSync));
      } catch (_) {
        lastSyncLabel.value = 'Nunca sincronizado';
      }
    }

    final results = await Connectivity().checkConnectivity();
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    isOnline.value = hasNet;
    if (hasNet) {
      await syncAllData();
    }
    await updatePendingCount();

    Connectivity().onConnectivityChanged.listen((results) async {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      final wasOnline = isOnline.value;
      isOnline.value = hasNet;
      if (hasNet) {
        await syncAllData();
      }
      await updatePendingCount();

      // Solo avisar en la transición, no en cada evento de conectividad.
      if (wasOnline != hasNet) {
        if (hasNet) {
          await NotificationService.showConnectivityNotice(
            title: 'Conexión restablecida',
            body: 'Los registros pendientes se están sincronizando.',
          );
        } else {
          await NotificationService.showConnectivityNotice(
            title: 'Sin conexión',
            body: 'La ronda sigue registrándose localmente y se sincronizará al reconectar.',
          );
        }
      }
    });
  }

  static Future<bool> checkConnectivityStatus() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  static String _formatSyncLabel(DateTime timestamp) {
    return 'Último sync: ${timestamp.toLocal().toString().substring(0, 19)}';
  }

  static void _updateLastSyncLabel(DateTime timestamp) {
    lastSyncLabel.value = _formatSyncLabel(timestamp);
  }

  static Future<void> saveGPSRecord(Map<String, dynamic> record) async {
    final box = Hive.box(_gpsBoxName);
    await box.add(record);
    await updatePendingCount();
  }

  static Future<void> saveIncidentRecord(Map<String, dynamic> record) async {
    final box = Hive.box(_incidentBoxName);
    final sanitizedRecord = {
      ...record,
      'title': SecurityService.sanitizeInput(record['title']?.toString() ?? ''),
      'description': SecurityService.sanitizeInput(record['description']?.toString() ?? ''),
    };
    await box.add(sanitizedRecord);
    await updatePendingCount();
  }

  static Future<void> saveSystemLog(String type, String details, {String? userId}) async {
    final box = Hive.box(_logsBoxName);
    final log = {
      'event_type': type,
      'details': SecurityService.sanitizeInput(details),
      'created_at': DateTime.now().toIso8601String(),
    };
    if (userId != null) {
      log['user_id'] = userId;
    }
    await box.add(log);
    await updatePendingCount();
  }

  static List<Map<String, dynamic>> getLocalLogs() {
    final box = Hive.box(_logsBoxName);
    return box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Envía una posición vía RPC. Devuelve false si no hay sesión o falla la
  /// red, para que el llamador la deje en la cola local.
  static Future<bool> sendGPS(Map<String, dynamic> record) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      return await SupabaseConfig.client.rpc('record_gps', params: {
        'p_token': token,
        'p_latitude': record['latitude'],
        'p_longitude': record['longitude'],
        'p_accuracy': record['accuracy'],
        'p_is_mock': record['is_mock'] ?? false,
        'p_battery_level': record['battery_level'],
        'p_recorded_at': record['recorded_at'],
      }) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _sendIncident(Map<String, dynamic> record, String token) async {
    try {
      return await SupabaseConfig.client.rpc('record_incident', params: {
        'p_token': token,
        'p_title': record['title'] ?? '',
        'p_description': record['description'] ?? '',
        'p_photo_url': record['photo_url'],
        'p_recorded_at': record['recorded_at'],
      }) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _sendLog(Map<String, dynamic> record, String token) async {
    try {
      return await SupabaseConfig.client.rpc('record_log', params: {
        'p_token': token,
        'p_event_type': record['event_type'] ?? 'audit',
        'p_details': record['details'] ?? '',
        'p_created_at': record['created_at'],
      }) as bool;
    } catch (_) {
      return false;
    }
  }

  /// Vacía las colas locales enviando registro por registro.
  ///
  /// Va de a uno (antes era un insert en lote) porque cada RPC valida la sesión
  /// y deriva el user_id de ella. A cambio, un registro que falla ya no arrastra
  /// al resto: los que sí entran se borran de la cola.
  static Future<bool> syncAllData() async {
    if (!await checkConnectivityStatus()) return false;

    final token = await SessionService.getToken();
    if (token == null) return false;

    var success = true;

    Future<void> drain(String boxName, Future<bool> Function(Map<String, dynamic>) send) async {
      final box = Hive.box(boxName);
      if (box.isEmpty) return;
      // Se recorren las claves para poder borrar solo lo confirmado.
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(raw as Map);
        if (await send(item)) {
          await box.delete(key);
        } else {
          success = false;
          break; // Si el servidor rechaza, no tiene sentido seguir insistiendo.
        }
      }
    }

    await drain(_gpsBoxName, sendGPS);
    await drain(_incidentBoxName, (item) => _sendIncident(item, token));
    await drain(_logsBoxName, (item) => _sendLog(item, token));

    await updatePendingCount();
    if (success) {
      _updateLastSyncLabel(DateTime.now());
      final metaBox = Hive.box(_syncMetaBoxName);
      await metaBox.put('last_sync_at', DateTime.now().toIso8601String());
    }
    return success;
  }

  static Future<void> updatePendingCount() async {
    if (!Hive.isBoxOpen(_gpsBoxName) || !Hive.isBoxOpen(_incidentBoxName) || !Hive.isBoxOpen(_logsBoxName)) {
      return;
    }
    final gpsBox = Hive.box(_gpsBoxName);
    final incBox = Hive.box(_incidentBoxName);
    final logsBox = Hive.box(_logsBoxName);
    pendingSyncCount.value = gpsBox.length + incBox.length + logsBox.length;
  }
}
