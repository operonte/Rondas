import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

/// Mapa de posiciones de guardias sobre OpenStreetMap.
/// Se usa OSM en vez de Google Maps porque no requiere API key ni facturación.
class GuardsMap extends StatefulWidget {
  /// Registros crudos de `gps_logs` (más recientes primero).
  final List<Map<String, dynamic>> gpsLogs;

  /// Mapa de user_id -> nombre del guardia, para etiquetar los marcadores.
  final Map<String, String> guardNames;

  const GuardsMap({super.key, required this.gpsLogs, this.guardNames = const {}});

  @override
  State<GuardsMap> createState() => _GuardsMapState();
}

class _GuardsMapState extends State<GuardsMap> {
  final MapController _mapController = MapController();

  /// Una posición por guardia: la más reciente. `gpsLogs` ya viene ordenado
  /// descendente, así que el primero de cada user_id es el vigente.
  List<Map<String, dynamic>> get _latestPerGuard {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final log in widget.gpsLogs) {
      final lat = log['latitude'];
      final lng = log['longitude'];
      if (lat == null || lng == null) continue;
      final key = log['user_id']?.toString() ?? 'sin_guardia_${result.length}';
      if (seen.add(key)) result.add(log);
    }
    return result;
  }

  String _labelFor(Map<String, dynamic> log) {
    final userId = log['user_id']?.toString();
    if (userId == null) return 'Sin guardia asignado';
    return widget.guardNames[userId] ?? 'Guardia ${userId.substring(0, userId.length.clamp(0, 8))}';
  }

  void _showDetails(Map<String, dynamic> log) {
    final isMock = log['is_mock'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isMock ? Icons.gps_off : Icons.person_pin_circle,
                    color: isMock ? Colors.redAccent : AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_labelFor(log),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isMock)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('⚠ Posible GPS falso detectado',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            Text('Lat: ${log['latitude']}, Lng: ${log['longitude']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Precisión: ${log['accuracy'] ?? '—'} m',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Batería: ${log['battery_level'] ?? '—'}%',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Registrado: ${log['recorded_at'] ?? '—'}',
                style: const TextStyle(color: AppColors.textSubtle, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = _latestPerGuard;

    if (positions.isEmpty) {
      return const Center(
        child: Text('Sin posiciones GPS registradas todavía.', style: TextStyle(color: Colors.grey)),
      );
    }

    final points = positions
        .map((log) => LatLng(
              (log['latitude'] as num).toDouble(),
              (log['longitude'] as num).toDouble(),
            ))
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            initialCameraFit: points.length > 1
                ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48))
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.rondas.rondas',
            ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < positions.length; i++)
                  Marker(
                    point: points[i],
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _showDetails(positions[i]),
                      child: Tooltip(
                        message: _labelFor(positions[i]),
                        child: Icon(
                          positions[i]['is_mock'] == true ? Icons.gps_off : Icons.person_pin_circle,
                          size: 40,
                          color: positions[i]['is_mock'] == true ? Colors.redAccent : AppColors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Atribución obligatoria por la licencia de OpenStreetMap.
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: const Text('© OpenStreetMap', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text('${positions.length} guardia(s) en mapa',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
