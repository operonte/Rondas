import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/gps_service.dart';
import '../services/alert_service.dart';
import '../services/nfc_qr_service.dart';
import '../services/offline_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'installation_picker_view.dart';
import 'login_view.dart';

class GuardView extends StatefulWidget {
  const GuardView({super.key});

  @override
  State<GuardView> createState() => _GuardViewState();
}

class _GuardViewState extends State<GuardView> {
  static const _roundStartedKey = 'rondas_round_started';
  static const _roundStartedAtKey = 'rondas_round_started_at';

  String _currentUserName = 'Guardia';
  Map<String, dynamic>? _lastGps;
  List<Map<String, dynamic>> _todayLogs = [];
  Map<String, dynamic>? _activeAlert;
  bool _online = false;
  int _pendingSync = 0;
  String _lastSyncLabel = 'Nunca sincronizado';
  bool _roundStarted = false;
  DateTime? _roundStartTime;
  bool _nfcAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadSessionUser();
    _loadRoundState();
    _loadNfcAvailability();
    _startServices();
    OfflineService.isOnline.addListener(_syncStatusChanged);
    OfflineService.pendingSyncCount.addListener(_syncStatusChanged);
    OfflineService.lastSyncLabel.addListener(_syncStatusChanged);
    _syncStatusChanged();
  }

  Future<void> _loadSessionUser() async {
    final userName = await AuthService.getCurrentUserName();
    if (!mounted) return;
    setState(() {
      _currentUserName = userName;
    });
  }

  Future<void> _loadRoundState() async {
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getBool(_roundStartedKey) ?? false;
    final startedAtString = prefs.getString(_roundStartedAtKey);
    DateTime? startedAt;
    if (startedAtString != null) {
      startedAt = DateTime.tryParse(startedAtString);
    }
    if (!mounted) return;
    setState(() {
      _roundStarted = started;
      _roundStartTime = startedAt;
    });
  }

  void _startServices() {
    gpsService.startTracking((data) {
      if (mounted) {
        setState(() {
          _lastGps = data;
        });
        _loadLogs();
      }
    });

    alertService.initRealtimeAlerts((alert) {
      if (mounted) {
        setState(() {
          _activeAlert = alert;
        });
      }
    });

    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = OfflineService.getLocalLogs();
    if (!mounted) return;
    setState(() {
      _todayLogs = logs.reversed.toList();
    });
  }

  Future<void> _loadNfcAvailability() async {
    final available = await NfcQrService.nfcAvailable;
    if (!mounted) return;
    setState(() {
      _nfcAvailable = available;
    });
  }

  String _prettyLogType(String type) {
    switch (type) {
      case 'audit':
        return 'Auditoría';
      case 'round_start':
        return 'Inicio de ronda';
      case 'round_end':
        return 'Fin de ronda';
      case 'incident':
        return 'Incidente';
      case 'checkin_qr':
        return 'Check-in QR';
      case 'checkin_nfc':
        return 'Check-in NFC';
      case 'checkin_manual':
        return 'Check-in manual';
      case 'offline_event':
        return 'Evento offline';
      case 'low_battery':
        return 'Batería baja';
      case 'random_check':
        return 'Chequeo aleatorio';
      default:
        return type.isEmpty ? 'Desconocido' : type;
    }
  }

  Future<void> _toggleRoundState() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await AuthService.getCurrentUserId();

    if (_roundStarted) {
      final endedAt = DateTime.now();
      await prefs.setBool(_roundStartedKey, false);
      await prefs.remove(_roundStartedAtKey);
      await OfflineService.saveSystemLog(
        'round_end',
        'Ronda finalizada a las ${endedAt.toLocal().toString().substring(0, 19)}.',
        userId: userId,
      );
      if (!mounted) return;
      setState(() {
        _roundStarted = false;
        _roundStartTime = null;
      });
    } else {
      final startedAt = DateTime.now();
      await prefs.setBool(_roundStartedKey, true);
      await prefs.setString(_roundStartedAtKey, startedAt.toIso8601String());
      await OfflineService.saveSystemLog(
        'round_start',
        'Ronda iniciada a las ${startedAt.toLocal().toString().substring(0, 19)}.',
        userId: userId,
      );
      if (!mounted) return;
      setState(() {
        _roundStarted = true;
        _roundStartTime = startedAt;
      });
    }
  }

  void _syncStatusChanged() {
    if (!mounted) return;
    setState(() {
      _online = OfflineService.isOnline.value;
      _pendingSync = OfflineService.pendingSyncCount.value;
      _lastSyncLabel = OfflineService.lastSyncLabel.value;
    });
  }

  Future<void> _runManualSync() async {
    if (!mounted) return;
    final snackBar = ScaffoldMessenger.of(context);
    final success = await OfflineService.syncAllData();
    if (!mounted) return;
    if (success) {
      snackBar.showSnackBar(
        const SnackBar(content: Text('Sincronización manual completada.'), backgroundColor: Colors.green),
      );
      _loadLogs();
    } else {
      snackBar.showSnackBar(
        const SnackBar(content: Text('Sincronización manual incompleta. Reintentará automáticamente.'), backgroundColor: Colors.orange),
      );
    }
  }

  /// Abre la cámara y sube la foto a Supabase Storage. Devuelve `null` si el
  /// guardia cancela la captura o si falla (sin conexión, etc.) -- la foto
  /// es un adjunto opcional, nunca bloquea el reporte de un incidente real.
  Future<String?> _capturePhotoAndUpload(String folder) async {
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (shot == null) return null;
      final Uint8List bytes = await shot.readAsBytes();
      return await StorageService.uploadPhoto(bytes, folder);
    } catch (_) {
      return null;
    }
  }

  void _openReportDialog() {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? photoUrl;
    bool capturingPhoto = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Reportar Novedad / Incidente', style: TextStyle(color: Colors.white)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Título de la novedad',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El título es obligatorio';
                      }
                      if (value.trim().length < 4) {
                        return 'Escribe un título más descriptivo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Detalles del incidente',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Detalle el incidente';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: capturingPhoto
                          ? null
                          : () async {
                              setDialogState(() => capturingPhoto = true);
                              final url = await _capturePhotoAndUpload('incidents');
                              setDialogState(() {
                                capturingPhoto = false;
                                photoUrl = url;
                              });
                            },
                      icon: Icon(
                        photoUrl != null ? Icons.check_circle : Icons.camera_alt,
                        color: photoUrl != null ? const Color(0xFF22C55E) : AppColors.accent,
                      ),
                      label: Text(
                        capturingPhoto
                            ? 'Subiendo foto...'
                            : (photoUrl != null ? 'Foto adjuntada' : 'Adjuntar foto (opcional)'),
                        style: TextStyle(color: photoUrl != null ? const Color(0xFF22C55E) : AppColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final rec = {
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'photo_url': photoUrl,
                    'recorded_at': DateTime.now().toIso8601String(),
                  };
                  await OfflineService.saveIncidentRecord(rec);
                  final userId = await AuthService.getCurrentUserId();
                  await OfflineService.saveSystemLog(
                    'incident',
                    'Novedad registrada: ${titleCtrl.text.trim()}',
                    userId: userId,
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  _loadLogs();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
                child: const Text('Guardar Novedad', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmAlertResponse() async {
    if (_activeAlert != null) {
      final alertId = _activeAlert!['id'].toString();
      final photoUrl = await _capturePhotoAndUpload('alerts');
      await alertService.respondAlert(alertId, photoUrl);
      setState(() {
        _activeAlert = null;
      });
      _loadLogs();
    }
  }

  Future<void> _performCheckIn() async {
    final navigator = Navigator.of(context);
    Map<String, String>? scanResult;

    if (_nfcAvailable) {
      scanResult = await NfcQrService.scanNFC();
    }

    scanResult ??= await NfcQrService.scanQR(navigator);

    if (scanResult == null) {
      final useManual = await _confirmManualCheckInFallback();
      if (useManual) {
        await _openManualCheckInDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in cancelado.')),
        );
      }
      return;
    }

    final userId = await AuthService.getCurrentUserId();
    final location = scanResult['location'] ?? 'Punto de control desconocido';
    final scanType = scanResult['scan_type'] ?? 'checkin';
    final scanLabel = scanType == 'checkin_qr'
        ? 'QR'
        : scanType == 'checkin_nfc'
            ? 'NFC'
            : scanType == 'checkin_manual'
                ? 'manual'
                : scanType;

    await OfflineService.saveSystemLog(
      scanType,
      'Check-in $scanLabel realizado en $location.',
      userId: userId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Check-in realizado en $location.'),
        backgroundColor: Colors.green,
      ),
    );
    _loadLogs();
  }

  Future<bool> _confirmManualCheckInFallback() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Usar Check-in manual?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'No se detectó QR ni NFC. ¿Deseas continuar con un check-in manual?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentStrong),
            child: const Text('Continuar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _openManualCheckInDialog() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final locationController = TextEditingController();

    final location = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Check-in manual', style: TextStyle(color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'QR/NFC no disponible. Ingresa el nombre del punto de control manualmente.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: locationController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nombre del punto de control',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Describe el punto de control';
                  }
                  if (value.trim().length < 3) {
                    return 'Escribe un nombre válido';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, locationController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (location == null || !mounted) return;
    final userId = await AuthService.getCurrentUserId();
    if (!mounted) return;

    await OfflineService.saveSystemLog(
      'checkin_manual',
      'Check-in manual realizado en $location.',
      userId: userId,
    );

    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Check-in manual guardado.'),
        backgroundColor: Colors.green,
      ),
    );
    _loadLogs();
  }

  @override
  void dispose() {
    OfflineService.isOnline.removeListener(_syncStatusChanged);
    OfflineService.pendingSyncCount.removeListener(_syncStatusChanged);
    OfflineService.lastSyncLabel.removeListener(_syncStatusChanged);
    gpsService.stopTracking();
    alertService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.security, color: AppColors.accent),
                SizedBox(width: 8),
                Text('Panel Guardia - Ronda Activa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 4),
            Text(_currentUserName, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        actions: [
          // Cambiar de sitio sin cerrar sesión: el guardia puede cubrir más de
          // una instalación en el mismo turno.
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: AppColors.accent),
            tooltip: 'Cambiar de instalación',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final name = await AuthService.getCurrentUserName();
              await AuthService.leaveInstallation();
              if (!mounted) return;
              navigator.pushReplacement(MaterialPageRoute(
                builder: (_) => InstallationPickerView(guardName: name),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AuthService.logout();
              if (!mounted) return;
              navigator.pushReplacement(MaterialPageRoute(builder: (_) => const LoginView()));
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card de Estado GPS continuo 100s
                Semantics(
                  container: true,
                  label: _lastGps != null
                      ? 'Estado del rastreo GPS. ${_lastGps!['is_mock'] == true ? 'Advertencia: GPS falso detectado. ' : ''}'
                          '${_online ? 'Conectado' : 'Sin conexión'}. $_pendingSync registros pendientes de sincronizar.'
                      : 'Inicializando rastreo GPS. ${_online ? 'Conectado' : 'Sin conexión'}.',
                  child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed, color: Color(0xFF10B981), size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Rastreo GPS Automático (Cada 100s)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  _lastGps != null
                                      ? 'Lat: ${_lastGps!['latitude'].toStringAsFixed(5)}, Lng: ${_lastGps!['longitude'].toStringAsFixed(5)}'
                                      : 'Inicializando posicionamiento GPS...',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                if (_lastGps != null && _lastGps!['is_mock'] == true)
                                  const Text('⚠️ ADVERTENCIA: GPS Falso detectado', style: TextStyle(color: Colors.amber, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_online ? Icons.wifi : Icons.wifi_off, color: _online ? Colors.greenAccent : Colors.redAccent),
                              const SizedBox(width: 8),
                              Text(
                                _online ? 'Conectado' : 'Sin conexión',
                                style: TextStyle(color: _online ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                'Pendientes: $_pendingSync',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _lastSyncLabel,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _runManualSync,
                                icon: const Icon(Icons.sync, color: Colors.white, size: 16),
                                label: const Text('Sync', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentStrong,
                                  minimumSize: const Size(70, 30),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _roundStarted ? Icons.flag_circle : Icons.flag_outlined,
                            color: _roundStarted ? Colors.greenAccent : Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _roundStarted ? 'Ronda en curso' : 'Ronda detenida',
                              style: TextStyle(
                                color: _roundStarted ? Colors.greenAccent : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_roundStarted && _roundStartTime != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Inicio: ${_roundStartTime!.toLocal().toString().substring(11, 19)}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _toggleRoundState,
                        icon: Icon(
                          _roundStarted ? Icons.stop_circle : Icons.play_circle,
                          color: Colors.white,
                        ),
                        label: Text(
                          _roundStarted ? 'FINALIZAR RONDA' : 'INICIAR RONDA',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _roundStarted ? Colors.redAccent : const Color(0xFF22C55E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      _nfcAvailable ? Icons.nfc : Icons.signal_cellular_off,
                      color: _nfcAvailable ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nfcAvailable
                            ? 'NFC disponible. Se intentará primero NFC, luego QR.'
                            : 'NFC no disponible. Se usará QR o entrada manual.',
                        style: TextStyle(
                          color: _nfcAvailable ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      tooltip: 'Verificar estado NFC',
                      onPressed: _loadNfcAvailability,
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white54),
                      tooltip: 'Más información sobre NFC',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: const Text('Sobre NFC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            content: const Text(
                              'El estado NFC puede ser "no disponible" si el dispositivo no tiene hardware NFC, '
                              'si está en modo avión, o si la aplicación no tiene permisos necesarios. '
                              'Pulsa "Verificar" para reintentar la detección.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar', style: TextStyle(color: Colors.grey))),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _performCheckIn,
                  icon: const Icon(Icons.qr_code, color: Colors.white),
                  label: const Text('CHECK-IN QR/NFC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentStrong,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Si no se detecta QR/NFC, usa CHECK-IN MANUAL para continuar el registro.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _openManualCheckInDialog,
                  icon: const Icon(Icons.edit_location_alt, color: Colors.white),
                  label: const Text('CHECK-IN MANUAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B5563),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _openReportDialog,
                  icon: const Icon(Icons.add_alert, color: Colors.white),
                  label: const Text('REPORTAR NOVEDAD / INCIDENTE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),

                // Titulo Historial del Día
                const Text('LOGS Y ACTIVIDAD DEL DÍA (OFICIAL)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // Lista del Log Diario
                Expanded(
                  child: _todayLogs.isEmpty
                      ? const Center(child: Text('No hay registros guardados hoy.', style: TextStyle(color: AppColors.textSubtle)))
                      : ListView.builder(
                          itemCount: _todayLogs.length,
                          itemBuilder: (ctx, i) {
                            final log = _todayLogs[i];
                            final type = log['event_type']?.toString() ?? '';
                            final isIncident = type == 'incident';
                            final isOffline = type == 'offline_event';
                            final isCheckIn = type == 'checkin_qr' || type == 'checkin_nfc' || type == 'checkin_manual';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isIncident
                                      ? const Color(0x80FFC107)
                                      : isOffline
                                          ? const Color(0x80FF5252)
                                          : isCheckIn
                                              ? const Color(0x8038BDF8)
                                              : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isIncident
                                        ? Icons.warning_amber
                                        : isOffline
                                            ? Icons.wifi_off
                                            : isCheckIn
                                                ? Icons.qr_code
                                                : Icons.check_circle_outline,
                                    color: isIncident
                                        ? Colors.amber
                                        : isOffline
                                            ? Colors.redAccent
                                            : isCheckIn
                                                ? AppColors.accent
                                                : Colors.greenAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(log['details'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                        const SizedBox(height: 6),
                                        if (isCheckIn)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            margin: const EdgeInsets.only(bottom: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E3A8A),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _prettyLogType(type),
                                              style: const TextStyle(color: Colors.white, fontSize: 11),
                                            ),
                                          ),
                                        Text(
                                          '${_prettyLogType(type)} · ${log['created_at']?.toString().substring(11, 19) ?? ''}${log['user_id'] != null ? ' · Guardia: ${log['user_id']}' : ''}',
                                          style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Modal Bloqueante a Pantalla Completa para Alertas.
          // liveRegion: el lector de pantalla la anuncia al aparecer, sin que
          // el guardia tenga que estar navegando la pantalla.
          if (_activeAlert != null)
            Semantics(
              container: true,
              liveRegion: true,
              label: _activeAlert!['type'] == 'low_battery'
                  ? 'Alerta activada. Batería crítica menor al 15 por ciento. Confirme recepción.'
                  : 'Alerta activada. Verificación de ronda solicitada por central. Confirme recepción.',
              child: Container(
              color: const Color(0xF2B71C1C),
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.notification_important, size: 90, color: Colors.white),
                    const SizedBox(height: 20),
                    const Text(
                      '¡ALERTA PERSISTENTE ACTIVADA!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _activeAlert!['type'] == 'low_battery'
                          ? 'Batería crítica menor al 15%. Confirme recepción.'
                          : 'Verificación aleatoria de ronda solicitada por central.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                      onPressed: _confirmAlertResponse,
                      icon: const Icon(Icons.camera_alt, color: Colors.black),
                      label: const Text('CONFIRMAR CHECK-IN / FOTO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
        ],
      ),
    );
  }
}
