import 'package:hive_flutter/hive_flutter.dart';
import '../config/supabase_config.dart';
import 'offline_service.dart';
import 'security_service.dart';
import 'session_service.dart';

class InstallationItem {
  final String id;
  final String name;
  final String accessCode;
  final String? address;

  InstallationItem({
    required this.id,
    required this.name,
    required this.accessCode,
    this.address,
  });

  factory InstallationItem.fromMap(Map<String, dynamic> map) {
    return InstallationItem(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      accessCode: map['access_code'] ?? '',
      address: map['address'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'access_code': accessCode,
      'address': address,
    };
  }
}

class InstallationService {
  static const String _boxName = 'cached_installations';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  /// Solo el superusuario obtiene el listado con los códigos de acceso: la
  /// función `admin_installations` valida el token y devuelve vacío para
  /// cualquier otro rol. Antes esto era un `select` abierto sobre la tabla.
  static Future<List<InstallationItem>> getInstallations() async {
    await init();
    final box = Hive.box(_boxName);

    final token = await SessionService.getToken();
    if (token != null && await OfflineService.checkConnectivityStatus()) {
      try {
        final res = await SupabaseConfig.client.rpc('admin_installations', params: {'p_token': token});
        final list = (res as List).map((e) => InstallationItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();

        if (list.isNotEmpty) {
          await box.clear();
          for (var item in list) {
            await box.put(item.id, item.toMap());
          }
        }
        return list;
      } catch (_) {}
    }

    // Retorno en modo offline desde caché Hive
    return box.values.map((e) => InstallationItem.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  static Future<bool> createInstallation(String name, String accessCode, String? address) async {
    return _upsert(name, accessCode, address, null);
  }

  static Future<bool> updateInstallation(String id, String name, String accessCode, String? address) async {
    return _upsert(name, accessCode, address, id);
  }

  static Future<bool> _upsert(String name, String accessCode, String? address, String? id) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      final ok = await SupabaseConfig.client.rpc('admin_upsert_installation', params: {
        'p_token': token,
        'p_name': SecurityService.sanitizeInput(name),
        'p_access_code': accessCode.trim(),
        'p_address': address != null ? SecurityService.sanitizeInput(address) : null,
        'p_id': id,
      }) as bool;
      if (ok) await getInstallations();
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteInstallation(String id) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      final ok = await SupabaseConfig.client.rpc(
        'admin_delete_installation',
        params: {'p_token': token, 'p_id': id},
      ) as bool;
      if (ok) await getInstallations();
      return ok;
    } catch (_) {
      return false;
    }
  }
}
