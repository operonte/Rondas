/// Una ronda: quién, cuándo empezó y cuándo terminó.
/// `end == null` significa que sigue en curso (o que el guardia nunca la cerró).
class RoundSummary {
  final String guardId;
  final DateTime start;
  final DateTime? end;

  const RoundSummary({required this.guardId, required this.start, this.end});

  bool get isOngoing => end == null;

  Duration durationUntil(DateTime now) => (end ?? now).difference(start);
}

/// Empareja eventos `round_start` / `round_end` por guardia.
///
/// [systemLogs] son filas crudas de `system_logs`; se acepta cualquier orden,
/// la función ordena por `created_at` antes de emparejar. El resultado sale
/// ordenado por inicio descendente (lo más reciente primero).
List<RoundSummary> buildRoundSummaries(List<Map<String, dynamic>> systemLogs) {
  final events = systemLogs
      .where((log) => log['event_type'] == 'round_start' || log['event_type'] == 'round_end')
      .map((log) => (log: log, at: DateTime.tryParse(log['created_at']?.toString() ?? '')))
      .where((e) => e.at != null)
      .toList()
    ..sort((a, b) => a.at!.compareTo(b.at!));

  final openByGuard = <String, RoundSummary>{};
  final summaries = <RoundSummary>[];

  for (final event in events) {
    final guardId = event.log['user_id']?.toString() ?? 'sin_guardia';

    if (event.log['event_type'] == 'round_start') {
      // Dos round_start seguidos sin cerrar: el anterior queda sin fin en vez
      // de descartarse -- perder una ronda del historial sería peor.
      final previous = openByGuard[guardId];
      if (previous != null) summaries.add(previous);
      openByGuard[guardId] = RoundSummary(guardId: guardId, start: event.at!);
    } else {
      final open = openByGuard.remove(guardId);
      // Un round_end sin round_start previo se ignora: no hay inicio que reportar.
      if (open != null) {
        summaries.add(RoundSummary(guardId: guardId, start: open.start, end: event.at!));
      }
    }
  }

  summaries.addAll(openByGuard.values);
  summaries.sort((a, b) => b.start.compareTo(a.start));
  return summaries;
}
