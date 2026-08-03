import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/supabase_config.dart';
import '../services/auth_service.dart';
import '../services/installation_service.dart';
import '../services/offline_service.dart';
import '../services/round_summary.dart';
import '../services/security_service.dart';
import '../services/session_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/guards_map.dart';
import 'login_view.dart';

class SuperView extends StatefulWidget {
  const SuperView({super.key});

  @override
  State<SuperView> createState() => _SuperViewState();
}

class _SuperViewState extends State<SuperView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _gpsLogs = [];
  List<Map<String, dynamic>> _systemLogs = [];
  List<Map<String, dynamic>> _incidents = [];
  List<InstallationItem> _installations = [];
  List<Map<String, dynamic>> _guardProfiles = [];
  bool _isLoading = true;
  bool _online = false;
  int _pendingSync = 0;
  String _lastSyncLabel = 'Nunca sincronizado';
  String _selectedLogType = 'Todas';
  final TextEditingController _logSearchController = TextEditingController();
  final Map<String, String> _logTypeOptions = {
    'Todas': 'Todas',
    'audit': 'Auditoría',
    'round_start': 'Inicio de ronda',
    'round_end': 'Fin de ronda',
    'incident': 'Incidente',
    'checkin_qr': 'Check-in QR',
    'checkin_nfc': 'Check-in NFC',
    'checkin_manual': 'Check-in manual',
    'offline_event': 'Evento offline',
    'low_battery': 'Batería baja',
    'random_check': 'Chequeo aleatorio',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchData();
    OfflineService.isOnline.addListener(_updateSyncState);
    OfflineService.pendingSyncCount.addListener(_updateSyncState);
    OfflineService.lastSyncLabel.addListener(_updateSyncState);
    _updateSyncState();
  }

  void _updateSyncState() {
    if (!mounted) return;
    setState(() {
      _online = OfflineService.isOnline.value;
      _pendingSync = OfflineService.pendingSyncCount.value;
      _lastSyncLabel = OfflineService.lastSyncLabel.value;
    });
  }

  /// user_id -> nombre, para mostrar quién es cada punto en el mapa y la lista
  /// de GPS en vez del UUID crudo.
  Map<String, String> get _guardNamesById => {
        for (final profile in _guardProfiles)
          if (profile['id'] != null) profile['id'].toString(): (profile['full_name']?.toString() ?? 'Guardia'),
      };

  List<RoundSummary> get _roundSummaries => buildRoundSummaries(_systemLogs);

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}min';
    return '${minutes}min';
  }

  List<Map<String, dynamic>> get _filteredSystemLogs {
    final filterType = _selectedLogType;
    final searchTerm = _logSearchController.text.trim().toLowerCase();
    return _systemLogs.where((log) {
      if (filterType != 'Todas' && (log['event_type']?.toString() ?? '') != filterType) {
        return false;
      }
      if (searchTerm.isEmpty) return true;
      final details = (log['details'] ?? '').toString().toLowerCase();
      final eventType = (log['event_type'] ?? '').toString().toLowerCase();
      final userId = (log['user_id'] ?? '').toString().toLowerCase();
      return details.contains(searchTerm) || eventType.contains(searchTerm) || userId.contains(searchTerm);
    }).toList();
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

  IconData _logIcon(String type) {
    switch (type) {
      case 'audit':
        return Icons.admin_panel_settings;
      case 'round_start':
        return Icons.play_circle;
      case 'round_end':
        return Icons.stop_circle;
      case 'incident':
        return Icons.warning_amber;
      case 'checkin_qr':
      case 'checkin_nfc':
      case 'checkin_manual':
        return Icons.qr_code;
      case 'offline_event':
        return Icons.wifi_off;
      case 'low_battery':
        return Icons.battery_alert;
      case 'random_check':
        return Icons.help_outline;
      default:
        return Icons.list_alt;
    }
  }

  Color _logIconColor(String type) {
    switch (type) {
      case 'audit':
        return AppColors.accent;
      case 'round_start':
      case 'round_end':
        return const Color(0xFF22C55E);
      case 'incident':
        return Colors.amber;
      case 'checkin_qr':
      case 'checkin_nfc':
      case 'checkin_manual':
        return AppColors.accentStrong;
      case 'offline_event':
        return Colors.redAccent;
      case 'low_battery':
        return const Color(0xFFF97316);
      case 'random_check':
        return const Color(0xFFFCD34D);
      default:
        return AppColors.accent;
    }
  }

  Color _logChipColor(String type) {
    switch (type) {
      case 'audit':
        return AppColors.accent;
      case 'round_start':
      case 'round_end':
        return const Color(0xFF22C55E);
      case 'incident':
        return const Color(0xFFf59e0b);
      case 'checkin_qr':
      case 'checkin_nfc':
      case 'checkin_manual':
        return AppColors.accentStrong;
      case 'offline_event':
        return const Color(0xFFEF4444);
      case 'low_battery':
        return const Color(0xFFF97316);
      case 'random_check':
        return const Color(0xFFfacc15);
      case 'Todas':
        return AppColors.accent;
      default:
        return AppColors.accent;
    }
  }

  Future<void> _runManualSync() async {
    if (!mounted) return;
    final snackBar = ScaffoldMessenger.of(context);
    final success = await OfflineService.syncAllData();
    if (!mounted) return;
    snackBar.showSnackBar(
      SnackBar(
        content: Text(success ? 'Sincronización manual completada.' : 'Sincronización manual incompleta. Reintentará automáticamente.'),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );
    if (success) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() { _isLoading = true; });
    try {
      final token = await SessionService.getToken();
      if (token == null) {
        setState(() { _isLoading = false; });
        return;
      }
      // Todo pasa por funciones admin_* que validan el token y exigen rol
      // superusuario; las tablas ya no aceptan consultas directas.
      final gpsRes = await SupabaseConfig.client.rpc('admin_gps_logs', params: {'p_token': token, 'p_limit': 100});
      // 200 y no 20: con 20 no alcanzaba para emparejar round_start/round_end
      // y armar los resúmenes de ronda.
      final logsRes = await SupabaseConfig.client.rpc('admin_system_logs', params: {'p_token': token, 'p_limit': 200});
      final incidentsRes = await SupabaseConfig.client.rpc('admin_incidents', params: {'p_token': token, 'p_limit': 30});
      final insts = await InstallationService.getInstallations();
      final guardProfiles = await AuthService.getGuardProfiles();
      final installationNames = {for (var item in insts) item.id: item.name};

      setState(() {
        _gpsLogs = List<Map<String, dynamic>>.from(gpsRes);
        _systemLogs = List<Map<String, dynamic>>.from(logsRes);
        _incidents = List<Map<String, dynamic>>.from(incidentsRes);
        _installations = insts;
        _guardProfiles = guardProfiles.map((profile) {
          return {
            ...profile,
            'installation_name': installationNames[profile['installation_id']?.toString()] ?? 'Sin instalación',
          };
        }).toList();
      });
    } catch (_) {}
    setState(() { _isLoading = false; });
  }

  Future<void> _triggerRandomAlert() async {
    try {
      final token = await SessionService.getToken();
      if (token == null) return;
      await SupabaseConfig.client.rpc('admin_trigger_alert', params: {
        'p_token': token,
        'p_type': 'random_check',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerta aleatoria enviada a guardias.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error enviando alerta: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showChangeSuperuserPasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cambiar contraseña Superusuario', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña actual',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true) ? 'Ingresa tu contraseña actual.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: newCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Ingresa la nueva contraseña.';
                    if (trimmed.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) {
                    if ((value?.trim().isEmpty ?? true)) return 'Confirma la nueva contraseña.';
                    if (value!.trim() != newCtrl.text.trim()) return 'Las contraseñas deben coincidir.';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final messenger = ScaffoldMessenger.of(context);
              final dialogNavigator = Navigator.of(dialogCtx);
              final currentPassword = currentCtrl.text.trim();
              final newPassword = newCtrl.text.trim();
              final success = await AuthService.updateSuperuserPassword(currentPassword, newPassword);
              if (success) {
                final userName = await AuthService.getCurrentUserName();
                final userId = await AuthService.getCurrentUserId();
                await OfflineService.saveSystemLog(
                  'audit',
                  '$userName actualizó su contraseña de superusuario.',
                  userId: userId,
                );
              }
              if (!mounted) return;
              dialogNavigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text(success ? 'Contraseña actualizada correctamente.' : 'No se pudo actualizar la contraseña.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            child: const Text('Actualizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openInstallationModal([InstallationItem? existingItem]) {
    final nameCtrl = TextEditingController(text: existingItem?.name ?? '');
    final passCtrl = TextEditingController(text: existingItem?.accessCode ?? '');
    final addrCtrl = TextEditingController(text: existingItem?.address ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          existingItem == null ? 'Crear Nueva Instalación' : 'Editar Instalación',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la Instalación (ej. demo)',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true) ? 'Ingresa el nombre de la instalación.' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: passCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Contraseña de Acceso Guardia',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (existingItem == null && trimmed.isEmpty) {
                            return 'Ingresa una contraseña para la instalación.';
                          }
                          if (trimmed.isNotEmpty && trimmed.length < 6) {
                            return 'Usa al menos 6 caracteres (o el botón de generar).';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.accent),
                      tooltip: 'Generar contraseña segura',
                      onPressed: () {
                        passCtrl.text = SecurityService.generateSecurePassword();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: addrCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Dirección o Ubicación (Opcional)',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) {
                    if (value != null && value.length > 200) {
                      return 'La dirección no puede superar 200 caracteres.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final messenger = ScaffoldMessenger.of(context);
              final installationName = SecurityService.sanitizeInput(nameCtrl.text.trim());
              final accessCode = SecurityService.sanitizeInput(passCtrl.text.trim());
              final location = addrCtrl.text.trim().isEmpty ? null : SecurityService.sanitizeInput(addrCtrl.text.trim());
              bool ok = false;
              final userName = await AuthService.getCurrentUserName();
              if (existingItem == null) {
                ok = await InstallationService.createInstallation(installationName, accessCode, location);
                if (ok) {
                  final userId = await AuthService.getCurrentUserId();
                  await OfflineService.saveSystemLog(
                    'audit',
                    '$userName creó la instalación "$installationName".',
                    userId: userId,
                  );
                }
              } else {
                ok = await InstallationService.updateInstallation(existingItem.id, installationName, accessCode, location);
                if (ok) {
                  final userId = await AuthService.getCurrentUserId();
                  await OfflineService.saveSystemLog(
                    'audit',
                    '$userName actualizó la instalación "$installationName".',
                    userId: userId,
                  );
                }
              }
              if (!mounted) return;
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (ok) _fetchData();
              messenger.showSnackBar(
                SnackBar(content: Text(ok ? 'Instalación guardada correctamente.' : 'No fue posible guardar la instalación.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            child: Text(existingItem == null ? 'Crear' : 'Guardar', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteInstallation(InstallationItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar Instalación', style: TextStyle(color: Colors.redAccent)),
        content: Text('¿Confirmas eliminar la instalación "${item.name}"?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final userName = await AuthService.getCurrentUserName();
              final deleted = await InstallationService.deleteInstallation(item.id);
              if (deleted) {
                final userId = await AuthService.getCurrentUserId();
                await OfflineService.saveSystemLog(
                  'audit',
                  '$userName eliminó la instalación "${item.name}".',
                  userId: userId,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _fetchData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openGuardProfileModal([Map<String, dynamic>? profile]) {
    final nameCtrl = TextEditingController(text: profile?['full_name'] ?? '');
    final passwordCtrl = TextEditingController();
    String? selectedInstallationId = profile?['installation_id']?.toString();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          profile == null ? 'Crear Guardia' : 'Editar Guardia',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo del guardia',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Ingresa el nombre del guardia.';
                    if (trimmed.length < 3) return 'El nombre debe tener al menos 3 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: profile == null ? 'Contraseña de acceso' : 'Nueva contraseña (dejar vacío para mantenerla)',
                    labelStyle: const TextStyle(color: AppColors.textMuted),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (profile == null && trimmed.isEmpty) return 'La contraseña es obligatoria para crear un guardia.';
                    if (trimmed.isNotEmpty && trimmed.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedInstallationId,
                  items: _installations.map((inst) {
                    return DropdownMenuItem<String>(
                      value: inst.id,
                      child: Text(inst.name, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (value) => selectedInstallationId = value,
                  decoration: const InputDecoration(
                    labelText: 'Instalación asignada',
                    labelStyle: TextStyle(color: AppColors.textMuted),
                  ),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white),
                  validator: (value) => value == null ? 'Selecciona una instalación.' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final messenger = ScaffoldMessenger.of(context);
              final dialogNavigator = Navigator.of(dialogCtx);
              final guardName = SecurityService.sanitizeInput(nameCtrl.text.trim());
              final guardPassword = passwordCtrl.text.trim();
              final installationId = selectedInstallationId!;

              final isNameAvailable = await AuthService.isGuardNameAvailable(
                guardName,
                excludeId: profile?['id']?.toString(),
              );
              if (!isNameAvailable) {
                messenger.showSnackBar(const SnackBar(content: Text('Ya existe un guardia con ese nombre.')));
                return;
              }

              late bool ok;
              if (profile == null) {
                ok = await AuthService.createGuardProfile(guardName, guardPassword, installationId);
                if (ok) {
                  final userName = await AuthService.getCurrentUserName();
                  final userId = await AuthService.getCurrentUserId();
                  await OfflineService.saveSystemLog(
                    'audit',
                    '$userName creó el guardia "$guardName".',
                    userId: userId,
                  );
                }
              } else {
                ok = await AuthService.updateGuardProfile(
                  profile['id'].toString(),
                  guardName,
                  guardPassword.isEmpty ? null : guardPassword,
                  installationId,
                );
                if (ok) {
                  final userName = await AuthService.getCurrentUserName();
                  final userId = await AuthService.getCurrentUserId();
                  await OfflineService.saveSystemLog(
                    'audit',
                    '$userName actualizó el guardia "$guardName".',
                    userId: userId,
                  );
                }
              }

              if (!mounted) return;
              dialogNavigator.pop();
              if (ok) _fetchData();
              messenger.showSnackBar(
                SnackBar(content: Text(ok ? 'Guardia guardado correctamente.' : 'No fue posible guardar el guardia.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            child: Text(profile == null ? 'Crear Guardia' : 'Guardar cambios', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteGuardProfile(Map<String, dynamic> profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar Guardia', style: TextStyle(color: Colors.redAccent)),
        content: Text('¿Eliminar al guardia "${profile['full_name']}"?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final userName = await AuthService.getCurrentUserName();
              final deleted = await AuthService.deleteGuardProfile(profile['id'].toString());
              if (deleted) {
                final userId = await AuthService.getCurrentUserId();
                await OfflineService.saveSystemLog(
                  'audit',
                  '$userName eliminó el guardia "${profile['full_name']}".',
                  userId: userId,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _fetchData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        // Título acortado y con Flexible: el anterior no entraba junto a los
        // botones y quedaba encimado.
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Central de Supervisión',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.business), text: 'Instalaciones'),
            Tab(icon: Icon(Icons.my_location), text: 'Posiciones GPS'),
            Tab(icon: Icon(Icons.list_alt), text: 'Logs Globales'),
            Tab(icon: Icon(Icons.report_problem_outlined), text: 'Incidentes'),
            Tab(icon: Icon(Icons.timer_outlined), text: 'Rondas'),
          ],
        ),
        // Solo recargar queda como botón directo; el resto va en un menú.
        // Antes había cuatro iconos más el estado de conexión y el contador de
        // pendientes acá arriba, y en pantalla de teléfono se superponían con
        // el título.
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.accent),
            tooltip: 'Recargar datos',
            onPressed: _fetchData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.accent),
            tooltip: 'Más opciones',
            color: AppColors.surface,
            onSelected: (value) async {
              switch (value) {
                case 'sync':
                  _runManualSync();
                  break;
                case 'password':
                  _showChangeSuperuserPasswordDialog();
                  break;
                case 'logout':
                  final navigator = Navigator.of(context);
                  await AuthService.logout();
                  if (!mounted) return;
                  navigator.pushReplacement(MaterialPageRoute(builder: (_) => const LoginView()));
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  leading: Icon(Icons.sync, color: AppColors.accent),
                  title: Text('Sincronizar ahora', style: TextStyle(color: Colors.white)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'password',
                child: ListTile(
                  leading: Icon(Icons.lock_reset, color: AppColors.accent),
                  title: Text('Cambiar contraseña', style: TextStyle(color: Colors.white)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.redAccent),
                  title: Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: ElevatedButton.icon(
                    onPressed: _triggerRandomAlert,
                    icon: const Icon(Icons.warning, color: Colors.black),
                    label: const Text('ACTIVAR ALERTA ALEATORIA A GUARDIAS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ),
                // Estado de conexión y pendientes: bajaron acá desde la barra
                // superior, donde no había espacio y se encimaban con el título.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      Icon(_online ? Icons.wifi : Icons.wifi_off,
                          size: 16, color: _online ? Colors.greenAccent : Colors.redAccent),
                      const SizedBox(width: 4),
                      Text(
                        _online ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: _online ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Pendientes: $_pendingSync',
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _runManualSync,
                        icon: const Icon(Icons.sync, color: Colors.white, size: 16),
                        label: const Text('Sync', style: TextStyle(color: Colors.white, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentStrong,
                          minimumSize: const Size(80, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_lastSyncLabel,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: GESTIÓN DE INSTALACIONES (CRUD)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _openInstallationModal(),
                              icon: const Icon(Icons.add_business, color: Colors.white),
                              label: const Text('CREAR NUEVA INSTALACIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _installations.isEmpty
                                  ? const Center(child: Text('No hay instalaciones registratas.', style: TextStyle(color: Colors.grey)))
                                  : ListView.builder(
                                      itemCount: _installations.length,
                                      itemBuilder: (ctx, i) {
                                        final item = _installations[i];
                                        return Card(
                                          color: AppColors.surface,
                                          margin: const EdgeInsets.only(bottom: 8),
                                          child: ListTile(
                                            leading: const Icon(Icons.shield, color: AppColors.accent),
                                            title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            subtitle: Text('Contraseña: ${item.accessCode}', style: const TextStyle(color: Colors.amber, fontSize: 13)),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.copy, color: Colors.white70),
                                                  tooltip: 'Copiar contraseña',
                                                  onPressed: () {
                                                    Clipboard.setData(ClipboardData(text: item.accessCode));
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('Contraseña copiada al portapapeles')),
                                                      );
                                                    }
                                                  },
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.edit, color: Colors.cyanAccent),
                                                  onPressed: () => _openInstallationModal(item),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                                  onPressed: () => _confirmDeleteInstallation(item),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Guardias Registrados', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  ElevatedButton.icon(
                                    onPressed: () => _openGuardProfileModal(),
                                    icon: const Icon(Icons.person_add, color: Colors.white),
                                    label: const Text('Agregar Guardia', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentStrong),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_guardProfiles.isEmpty)
                                    const Text('No hay guardias registrados.', style: TextStyle(color: Colors.grey))
                                  else
                                    Column(
                                      children: _guardProfiles.map((profile) {
                                        return Card(
                                          color: AppColors.surface,
                                          margin: const EdgeInsets.only(bottom: 8),
                                          child: ListTile(
                                            leading: const Icon(Icons.person, color: AppColors.accent),
                                            title: Text(profile['full_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            subtitle: Text('Instalación: ${profile['installation_name'] ?? 'Sin instalación'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, color: Colors.cyanAccent),
                                                  tooltip: 'Editar',
                                                  onPressed: () => _openGuardProfileModal(profile),
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
                                                  tooltip: 'Más acciones',
                                                  color: AppColors.surface,
                                                  onSelected: (v) {
                                                    if (v == 'reset') _resetGuardPassword(profile);
                                                    if (v == 'revoke') _revokeGuardSessions(profile);
                                                    if (v == 'delete') _confirmDeleteGuardProfile(profile);
                                                  },
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                      value: 'reset',
                                                      child: ListTile(
                                                        leading: Icon(Icons.key, color: AppColors.accent),
                                                        title: Text('Nueva contraseña', style: TextStyle(color: Colors.white)),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'revoke',
                                                      child: ListTile(
                                                        leading: Icon(Icons.phonelink_erase, color: Colors.orangeAccent),
                                                        title: Text('Cerrar sus sesiones', style: TextStyle(color: Colors.white)),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: ListTile(
                                                        leading: Icon(Icons.delete, color: Colors.redAccent),
                                                        title: Text('Eliminar guardia', style: TextStyle(color: Colors.redAccent)),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // TAB 2: MAPA / POSICIONES GPS
                      Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: GuardsMap(gpsLogs: _gpsLogs, guardNames: _guardNamesById),
                          ),
                          Expanded(
                            flex: 2,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _gpsLogs.length,
                              itemBuilder: (ctx, i) {
                                final item = _gpsLogs[i];
                                final isMock = item['is_mock'] == true;
                                final userId = item['user_id']?.toString();
                                return Card(
                                  color: AppColors.surface,
                                  child: ListTile(
                                    leading: Icon(
                                      isMock ? Icons.gps_off : Icons.my_location,
                                      color: isMock ? Colors.redAccent : const Color(0xFF10B981),
                                    ),
                                    title: Text(
                                      '${userId != null ? (_guardNamesById[userId] ?? 'Guardia') : 'Sin guardia'} · Lat: ${item['latitude']}, Lng: ${item['longitude']}',
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      'Batería: ${item['battery_level']}% | Fecha: ${item['recorded_at']}${isMock ? ' | ⚠ GPS falso' : ''}',
                                      style: TextStyle(color: isMock ? Colors.redAccent : Colors.grey, fontSize: 11),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      // TAB 3: LOGS GLOBALES
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _logTypeOptions.entries.map((entry) {
                                      final isSelected = _selectedLogType == entry.key;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          selected: isSelected,
                                          label: Text(
                                            entry.value,
                                            style: TextStyle(
                                              color: isSelected ? Colors.black : Colors.white,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                          selectedColor: _logChipColor(entry.key),
                                          backgroundColor: AppColors.surface,
                                          elevation: isSelected ? 4 : 0,
                                          shadowColor: isSelected ? _logChipColor(entry.key).withAlpha((0.35 * 255).round()) : null,
                                          labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          side: BorderSide(color: isSelected ? _logChipColor(entry.key) : AppColors.border),
                                          onSelected: (_) {
                                            setState(() {
                                              _selectedLogType = entry.key;
                                            });
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _logSearchController,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: const InputDecoration(
                                          labelText: 'Buscar logs',
                                          labelStyle: TextStyle(color: AppColors.textMuted),
                                          filled: true,
                                          fillColor: AppColors.surfaceAlt,
                                          suffixIcon: Icon(Icons.search, color: Colors.white54),
                                        ),
                                        onChanged: (_) {
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.accent,
                                        backgroundColor: AppColors.background,
                                        side: const BorderSide(color: AppColors.border),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _selectedLogType = 'Todas';
                                          _logSearchController.clear();
                                        });
                                      },
                                      icon: const Icon(Icons.clear, size: 18),
                                      label: const Text('Limpiar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Resultados: ${_filteredSystemLogs.length}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _filteredSystemLogs.isEmpty
                                  ? const Center(child: Text('No hay logs que coincidan con el filtro.', style: TextStyle(color: Colors.grey)))
                                  : ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: _filteredSystemLogs.length,
                                      itemBuilder: (ctx, i) {
                                        final log = _filteredSystemLogs[i];
                                        return Card(
                                          color: AppColors.surface,
                                          child: ListTile(
                                            leading: Icon(
                                              _logIcon(log['event_type']?.toString() ?? ''),
                                              color: _logIconColor(log['event_type']?.toString() ?? ''),
                                            ),
                                            title: Text(log['details'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _prettyLogType(log['event_type']?.toString() ?? ''),
                                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${log['created_at'] ?? ''}${log['user_id'] != null ? ' · Guardia: ${log['user_id']}' : ''}',
                                                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),

                      // TAB 4: INCIDENTES / NOVEDADES REPORTADAS
                      _incidents.isEmpty
                          ? const Center(child: Text('No hay incidentes reportados.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _incidents.length,
                              itemBuilder: (ctx, i) {
                                final item = _incidents[i];
                                final photoUrl = item['photo_url']?.toString();
                                return Card(
                                  color: AppColors.surface,
                                  child: ListTile(
                                    // La base guarda la ruta dentro del bucket
                                    // privado; la URL se firma acá y vence en
                                    // una hora.
                                    leading: photoUrl == null || photoUrl.isEmpty
                                        ? const Icon(Icons.warning_amber, color: Colors.amber)
                                        : FutureBuilder<String?>(
                                            future: StorageService.signedUrlFor(photoUrl),
                                            builder: (ctx, snap) {
                                              final url = snap.data;
                                              if (url == null) {
                                                return const Icon(Icons.image_outlined, color: Colors.grey);
                                              }
                                              return GestureDetector(
                                                onTap: () => _openPhotoPreview(url),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Image.network(
                                                    url,
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) =>
                                                        const Icon(Icons.broken_image, color: Colors.grey),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                    title: Text(item['title']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(item['description']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(item['recorded_at']?.toString() ?? '', style: const TextStyle(color: AppColors.textSubtle, fontSize: 11)),
                                      ],
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),

                      // TAB 5: RESÚMENES DE RONDA (inicio, fin, duración)
                      Builder(
                        builder: (ctx) {
                          final summaries = _roundSummaries;
                          if (summaries.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Todavía no hay rondas registradas.\nAparecerán cuando los guardias inicien y finalicen sus rondas.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          final inProgress = summaries.where((s) => s.isOngoing).length;
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _summaryTile(
                                        'Rondas registradas',
                                        '${summaries.length}',
                                        Icons.timer_outlined,
                                        AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _summaryTile(
                                        'En curso ahora',
                                        '$inProgress',
                                        Icons.directions_walk,
                                        inProgress > 0 ? const Color(0xFF22C55E) : AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: summaries.length,
                                  itemBuilder: (ctx, i) {
                                    final s = summaries[i];
                                    final start = s.start;
                                    final end = s.end;
                                    final guardName = _guardNamesById[s.guardId] ?? 'Sin guardia identificado';
                                    final ongoing = s.isOngoing;

                                    return Card(
                                      color: AppColors.surface,
                                      child: ListTile(
                                        leading: Icon(
                                          ongoing ? Icons.play_circle : Icons.check_circle,
                                          color: ongoing ? const Color(0xFF22C55E) : AppColors.accent,
                                        ),
                                        title: Text(
                                          guardName,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              'Inicio: ${start.toLocal().toString().substring(0, 19)}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                            Text(
                                              end == null
                                                  ? 'Fin: — (en curso)'
                                                  : 'Fin: ${end.toLocal().toString().substring(0, 19)}',
                                              style: TextStyle(
                                                color: ongoing ? const Color(0xFF22C55E) : Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Text(
                                          _formatDuration(s.durationUntil(DateTime.now())),
                                          style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        isThreeLine: true,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Repone la contraseña de un guardia sin pedir la anterior: el supervisor
  /// es quien las reparte y tiene que poder resolver un olvido.
  Future<void> _resetGuardPassword(Map<String, dynamic> profile) async {
    final controller = TextEditingController(text: SecurityService.generateSecurePassword());
    final name = profile['full_name']?.toString() ?? 'Guardia';

    final nueva = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Nueva contraseña de $name', style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'El guardia usará esta contraseña para entrar. Anotala antes de confirmar: después no se puede volver a ver.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                labelStyle: const TextStyle(color: AppColors.textMuted),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.accent),
                  tooltip: 'Generar otra',
                  onPressed: () => controller.text = SecurityService.generateSecurePassword(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            child: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (nueva == null || nueva.isEmpty || !mounted) return;
    final token = await SessionService.getToken();
    if (token == null) return;

    bool ok = false;
    try {
      ok = await SupabaseConfig.client.rpc('admin_reset_guard_password', params: {
        'p_token': token,
        'p_id': profile['id'].toString(),
        'p_new_hash': SecurityService.hashPassword(nueva),
      }) as bool;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Contraseña de $name actualizada: $nueva' : 'No se pudo cambiar la contraseña.'),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 8),
    ));
  }

  /// Cierra las sesiones abiertas de un guardia. Sirve si pierde el teléfono:
  /// sin esto, su sesión seguiría activa hasta vencer por su cuenta.
  Future<void> _revokeGuardSessions(Map<String, dynamic> profile) async {
    final name = profile['full_name']?.toString() ?? 'Guardia';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cerrar sesiones', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          'Se cerrará la sesión de $name en todos sus dispositivos. Va a tener que volver a ingresar su contraseña.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('CERRAR SESIONES', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    final token = await SessionService.getToken();
    if (token == null) return;

    int cerradas = 0;
    try {
      cerradas = await SupabaseConfig.client.rpc('admin_revoke_sessions', params: {
        'p_token': token,
        'p_profile_id': profile['id'].toString(),
      }) as int;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$cerradas sesión(es) cerradas de $name.'),
      backgroundColor: Colors.green,
    ));
  }

  Widget _summaryTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPhotoPreview(String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.network(
                photoUrl,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No se pudo cargar la imagen.', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    OfflineService.isOnline.removeListener(_updateSyncState);
    OfflineService.pendingSyncCount.removeListener(_updateSyncState);
    OfflineService.lastSyncLabel.removeListener(_updateSyncState);
    _logSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
}
