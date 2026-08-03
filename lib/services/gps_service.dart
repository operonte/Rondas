import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'auth_service.dart';
import 'offline_service.dart';

class GPSService {
  Timer? _timer;
  final Battery _battery = Battery();
  static const int intervalSeconds = 100;

  void startTracking(Function(Map<String, dynamic>)? onUpdate) {
    if (_timer != null) return;
    _captureLocation(onUpdate);
    _timer = Timer.periodic(const Duration(seconds: intervalSeconds), (_) {
      _captureLocation(onUpdate);
    });
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
  }

  bool _isMockLocation(Position pos) {
    if (pos.isMocked) return true;
    if (pos.accuracy > 300) return true;
    if (pos.speed > 25 && pos.altitude == 0) return true;
    return false;
  }

  Future<void> _captureLocation(Function(Map<String, dynamic>)? onUpdate) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      int batteryLevel = 100;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      bool isMock = _isMockLocation(pos);
      final timestamp = DateTime.now().toIso8601String();
      final userId = await AuthService.getCurrentUserId();
      final gpsData = {
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'is_mock': isMock,
        'battery_level': batteryLevel,
        'recorded_at': timestamp,
      };

      if (isMock) {
        await OfflineService.saveSystemLog(
          'mock_gps_detected',
          'Posible GPS Falso detectado: Lat ${pos.latitude}, Lng ${pos.longitude}, Precisión ${pos.accuracy}m',
          userId: userId,
        );
      }

      bool online = await OfflineService.checkConnectivityStatus();
      if (online) {
        // El servidor toma el user_id de la sesión, no de lo que mande el
        // cliente: nadie puede registrar posiciones a nombre de otro guardia.
        final sent = await OfflineService.sendGPS(gpsData);
        if (!sent) {
          await OfflineService.saveGPSRecord(gpsData);
        }
      } else {
        await OfflineService.saveGPSRecord(gpsData);
        await OfflineService.saveSystemLog(
          'offline_event',
          'GPS registrado en modo Offline',
          userId: userId,
        );
      }

      if (onUpdate != null) onUpdate(gpsData);

    } catch (e) {
      final userId = await AuthService.getCurrentUserId();
      await OfflineService.saveSystemLog(
        'offline_event',
        'Fallo capturando GPS: $e',
        userId: userId,
      );
    }
  }
}

final gpsService = GPSService();
