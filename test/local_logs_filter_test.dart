import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rondas/services/offline_service.dart';

/// La bitácora local es por dispositivo: si el supervisor y un guardia usan el
/// mismo teléfono, sus registros conviven en la misma caja. La vista del
/// guardia tiene que mostrar solo los suyos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/rondas_test_hive');
  });

  setUp(() async {
    if (Hive.isBoxOpen('logs_queue')) {
      await Hive.box('logs_queue').clear();
    } else {
      await Hive.openBox('logs_queue');
    }
    final box = Hive.box('logs_queue');
    await box.add({
      'event_type': 'audit',
      'details': 'Instalación creada por el supervisor',
      'user_id': 'super-1',
      'created_at': '2026-08-02T10:00:00Z',
    });
    await box.add({
      'event_type': 'round_start',
      'details': 'Ronda iniciada',
      'user_id': 'guard-1',
      'created_at': '2026-08-02T11:00:00Z',
    });
    await box.add({
      'event_type': 'round_start',
      'details': 'Ronda de otro guardia',
      'user_id': 'guard-2',
      'created_at': '2026-08-02T12:00:00Z',
    });
    await box.add({
      'event_type': 'offline_event',
      'details': 'Registro sin usuario',
      'created_at': '2026-08-02T13:00:00Z',
    });
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  group('OfflineService.getLocalLogs', () {
    test('sin filtro devuelve todo lo del dispositivo', () {
      expect(OfflineService.getLocalLogs().length, 4);
    });

    test('un guardia no ve la actividad del supervisor', () {
      final logs = OfflineService.getLocalLogs(userId: 'guard-1');
      expect(logs.length, 1);
      expect(logs.first['details'], 'Ronda iniciada');
      expect(logs.any((l) => l['user_id'] == 'super-1'), isFalse);
    });

    test('un guardia no ve las rondas de otro guardia', () {
      final logs = OfflineService.getLocalLogs(userId: 'guard-1');
      expect(logs.any((l) => l['user_id'] == 'guard-2'), isFalse);
    });

    test('el supervisor ve solo lo suyo al filtrar', () {
      final logs = OfflineService.getLocalLogs(userId: 'super-1');
      expect(logs.length, 1);
      expect(logs.first['event_type'], 'audit');
    });

    test('los registros sin usuario no se atribuyen a nadie', () {
      expect(OfflineService.getLocalLogs(userId: 'guard-1')
          .any((l) => l['details'] == 'Registro sin usuario'), isFalse);
      expect(OfflineService.getLocalLogs(userId: 'super-1')
          .any((l) => l['details'] == 'Registro sin usuario'), isFalse);
    });

    test('un usuario sin registros propios no ve nada ajeno', () {
      expect(OfflineService.getLocalLogs(userId: 'guard-desconocido'), isEmpty);
    });
  });
}
