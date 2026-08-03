import 'package:flutter_test/flutter_test.dart';
import 'package:rondas/services/round_summary.dart';

Map<String, dynamic> log(String type, String userId, String createdAt) => {
      'event_type': type,
      'user_id': userId,
      'created_at': createdAt,
    };

void main() {
  group('buildRoundSummaries', () {
    test('sin logs devuelve lista vacía', () {
      expect(buildRoundSummaries([]), isEmpty);
    });

    test('empareja un round_start con su round_end', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_end', 'g1', '2026-08-01T12:30:00Z'),
      ]);

      expect(result.length, 1);
      expect(result.first.guardId, 'g1');
      expect(result.first.isOngoing, isFalse);
      expect(result.first.durationUntil(DateTime.now()), const Duration(hours: 4, minutes: 30));
    });

    test('una ronda sin round_end queda en curso', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
      ]);

      expect(result.length, 1);
      expect(result.first.isOngoing, isTrue);
      expect(result.first.end, isNull);
    });

    test('acepta logs en orden descendente (como vienen de Supabase)', () {
      final result = buildRoundSummaries([
        log('round_end', 'g1', '2026-08-01T12:00:00Z'),
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
      ]);

      expect(result.length, 1);
      expect(result.first.isOngoing, isFalse);
      expect(result.first.durationUntil(DateTime.now()), const Duration(hours: 4));
    });

    test('separa rondas de guardias distintos aunque se solapen', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_start', 'g2', '2026-08-01T09:00:00Z'),
        log('round_end', 'g1', '2026-08-01T10:00:00Z'),
        log('round_end', 'g2', '2026-08-01T11:00:00Z'),
      ]);

      expect(result.length, 2);
      final g1 = result.firstWhere((s) => s.guardId == 'g1');
      final g2 = result.firstWhere((s) => s.guardId == 'g2');
      expect(g1.durationUntil(DateTime.now()), const Duration(hours: 2));
      expect(g2.durationUntil(DateTime.now()), const Duration(hours: 2));
    });

    test('dos round_start seguidos: el primero se conserva sin fin', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_start', 'g1', '2026-08-01T14:00:00Z'),
      ]);

      expect(result.length, 2);
      expect(result.every((s) => s.isOngoing), isTrue);
    });

    test('round_end sin round_start previo se ignora', () {
      final result = buildRoundSummaries([
        log('round_end', 'g1', '2026-08-01T12:00:00Z'),
      ]);

      expect(result, isEmpty);
    });

    test('ignora eventos que no son de ronda', () {
      final result = buildRoundSummaries([
        log('incident', 'g1', '2026-08-01T09:00:00Z'),
        log('checkin_qr', 'g1', '2026-08-01T09:30:00Z'),
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_end', 'g1', '2026-08-01T10:00:00Z'),
      ]);

      expect(result.length, 1);
      expect(result.first.durationUntil(DateTime.now()), const Duration(hours: 2));
    });

    test('descarta logs con created_at inválido en vez de romper', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', 'no-es-una-fecha'),
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_end', 'g1', '2026-08-01T09:00:00Z'),
      ]);

      expect(result.length, 1);
      expect(result.first.durationUntil(DateTime.now()), const Duration(hours: 1));
    });

    test('ordena de más reciente a más antigua', () {
      final result = buildRoundSummaries([
        log('round_start', 'g1', '2026-08-01T08:00:00Z'),
        log('round_end', 'g1', '2026-08-01T09:00:00Z'),
        log('round_start', 'g1', '2026-08-03T08:00:00Z'),
        log('round_end', 'g1', '2026-08-03T09:00:00Z'),
        log('round_start', 'g1', '2026-08-02T08:00:00Z'),
        log('round_end', 'g1', '2026-08-02T09:00:00Z'),
      ]);

      expect(result.length, 3);
      expect(result[0].start.isAfter(result[1].start), isTrue);
      expect(result[1].start.isAfter(result[2].start), isTrue);
    });

    test('logs sin user_id se agrupan bajo un guardia genérico', () {
      final result = buildRoundSummaries([
        {'event_type': 'round_start', 'created_at': '2026-08-01T08:00:00Z'},
        {'event_type': 'round_end', 'created_at': '2026-08-01T09:00:00Z'},
      ]);

      expect(result.length, 1);
      expect(result.first.guardId, 'sin_guardia');
    });
  });
}
