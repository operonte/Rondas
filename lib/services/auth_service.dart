import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import 'offline_service.dart';
import 'security_service.dart';
import 'session_service.dart';

enum UserRole { guardia, superusuario, none }

/// Autenticación contra las funciones RPC de Supabase.
///
/// El login devuelve un token de sesión que acredita rol e instalación en cada
/// llamada posterior. Las tablas no aceptan consultas directas con la anon key,
/// así que sin token la app no puede hacer nada (ver `security_sessions.sql`).
class AuthService {
  static const String _sessionRoleKey = 'rondas_user_role';
  static const String _sessionUserNameKey = 'rondas_user_name';
  static const String _sessionUserIdKey = 'rondas_user_id';
  static const String _sessionInstNameKey = 'rondas_inst_name';
  static const String _sessionInstIdKey = 'rondas_inst_id';

  static Future<Map<String, dynamic>> login({String? fullName, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanName = fullName?.trim();
    final sanitizedName = cleanName != null && cleanName.isNotEmpty
        ? SecurityService.sanitizeInput(cleanName)
        : null;
    // La contraseña nunca viaja en claro: el servidor compara hashes, incluso
    // para los códigos de acceso de instalación.
    final hashedPass = SecurityService.hashPassword(password.trim());

    if (!await OfflineService.checkConnectivityStatus()) {
      return {
        'success': false,
        'role': UserRole.none,
        'error': 'Sin conexión. Se necesita internet para iniciar sesión.',
      };
    }

    try {
      final rows = await SupabaseConfig.client.rpc(
        'login',
        params: {
          'p_password_hash': hashedPass,
          if (sanitizedName != null) 'p_full_name': sanitizedName,
        },
      ) as List<dynamic>;

      if (rows.isEmpty) {
        return {
          'success': false,
          'role': UserRole.none,
          'error': sanitizedName != null
              ? 'Usuario o contraseña no válidos'
              : 'Contraseña no válida',
        };
      }

      final row = rows.first as Map<String, dynamic>;
      await SessionService.setToken(row['token'].toString());

      final roleStr = row['role'] as String? ?? 'guardia';
      final displayName = row['display_name']?.toString() ?? 'Usuario';
      final profileId = row['profile_id']?.toString();

      // Cambio de usuario en el mismo dispositivo: la bitácora local es por
      // dispositivo, así que sin esto un guardia vería los registros que dejó
      // el supervisor (o el guardia anterior) al usar este mismo teléfono.
      final previousId = prefs.getString(_sessionUserIdKey);
      if (previousId != null && previousId != profileId) {
        await OfflineService.clearSyncedLogs();
      }
      if (profileId != null) {
        await prefs.setString(_sessionUserIdKey, profileId);
      } else {
        await prefs.remove(_sessionUserIdKey);
      }

      if (roleStr == 'superusuario') {
        await prefs.setString(_sessionRoleKey, 'superusuario');
        await prefs.setString(_sessionUserNameKey, displayName);
        await prefs.setString(_sessionInstNameKey, 'Central de Supervisión');
        return {
          'success': true,
          'role': UserRole.superusuario,
          'name': displayName,
          'installation_name': 'Central de Supervisión',
        };
      }

      // Guardia identificado por su contraseña personal. Todavía no eligió
      // instalación: la app le muestra la lista y le pide el código del sitio.
      await prefs.setString(_sessionRoleKey, 'guardia');
      await prefs.setString(_sessionUserNameKey, displayName);
      await prefs.remove(_sessionInstIdKey);
      await prefs.remove(_sessionInstNameKey);

      return {
        'success': true,
        'role': UserRole.guardia,
        'name': displayName,
        'requires_installation': true,
      };
    } catch (_) {
      return {
        'success': false,
        'role': UserRole.none,
        'error': 'No se pudo contactar al servidor. Reintenta.',
      };
    }
  }

  /// Instalaciones entre las que el guardia puede elegir. El servidor nunca
  /// devuelve el código de acceso: ese lo tiene que saber la persona.
  static Future<List<Map<String, dynamic>>> getAvailableInstallations() async {
    final token = await SessionService.getToken();
    if (token == null) return [];
    try {
      final result = await SupabaseConfig.client
          .rpc('available_installations', params: {'p_token': token});
      return List<Map<String, dynamic>>.from(result as List<dynamic>);
    } catch (_) {
      return [];
    }
  }

  /// Entra a la instalación elegida validando su código. Hasta completar esto,
  /// el servidor rechaza registrar GPS o incidentes: una ronda sin sitio
  /// asignado no se puede supervisar.
  static Future<bool> enterInstallation(String installationId, String accessCode) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      final rows = await SupabaseConfig.client.rpc('enter_installation', params: {
        'p_token': token,
        'p_installation_id': installationId,
        'p_access_code_hash': SecurityService.hashPassword(accessCode.trim()),
      }) as List<dynamic>;
      if (rows.isEmpty) return false;

      final row = rows.first as Map<String, dynamic>;
      if (row['ok'] != true) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionInstIdKey, installationId);
      await prefs.setString(
          _sessionInstNameKey, row['installation_name']?.toString() ?? 'Instalación');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sale de la instalación sin cerrar sesión, para cambiar de sitio en el
  /// mismo turno.
  static Future<void> leaveInstallation() async {
    final token = await SessionService.getToken();
    if (token != null) {
      try {
        await SupabaseConfig.client.rpc('leave_installation', params: {'p_token': token});
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionInstIdKey);
    await prefs.remove(_sessionInstNameKey);
  }

  static Future<UserRole> getCurrentRole() async {
    // Sin token no hay sesión utilizable, aunque queden restos en preferencias.
    if (await SessionService.getToken() == null) return UserRole.none;
    final prefs = await SharedPreferences.getInstance();
    final roleStr = prefs.getString(_sessionRoleKey);
    if (roleStr == 'guardia') return UserRole.guardia;
    if (roleStr == 'superusuario') return UserRole.superusuario;
    return UserRole.none;
  }

  static Future<String> getInstallationName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionInstNameKey) ?? 'Instalación';
  }

  static Future<void> logout() async {
    final token = await SessionService.getToken();
    if (token != null) {
      // Invalida la sesión también en el servidor: si solo se borrara local,
      // el token seguiría sirviendo hasta vencer.
      try {
        await SupabaseConfig.client.rpc('logout', params: {'p_token': token});
      } catch (_) {}
    }
    await SessionService.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionRoleKey);
    await prefs.remove(_sessionUserIdKey);
    await prefs.remove(_sessionUserNameKey);
    await prefs.remove(_sessionInstNameKey);
    await prefs.remove(_sessionInstIdKey);
  }

  static Future<String> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionUserNameKey) ?? 'Usuario';
  }

  static Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionUserIdKey);
  }

  static Future<String?> getCurrentInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionInstIdKey);
  }

  static Future<bool> updateSuperuserPassword(String currentPassword, String newPassword) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      return await SupabaseConfig.client.rpc(
        'admin_change_password',
        params: {
          'p_token': token,
          'p_current_hash': SecurityService.hashPassword(currentPassword.trim()),
          'p_new_hash': SecurityService.hashPassword(newPassword.trim()),
        },
      ) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isGuardNameAvailable(String fullName, {String? excludeId}) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      return await SupabaseConfig.client.rpc(
        'admin_guard_name_available',
        params: {'p_token': token, 'p_full_name': fullName.trim(), 'p_exclude_id': excludeId},
      ) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> createGuardProfile(String fullName, String password, String installationId) async {
    return _upsertGuard(fullName, password, installationId, null);
  }

  static Future<bool> updateGuardProfile(String id, String fullName, String? password, String installationId) async {
    return _upsertGuard(fullName, password, installationId, id);
  }

  static Future<bool> _upsertGuard(String fullName, String? password, String installationId, String? id) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      // Cadena vacía = "no cambiar la contraseña" (el servidor conserva la
      // existente); solo aplica al editar.
      final hash = (password != null && password.trim().isNotEmpty)
          ? SecurityService.hashPassword(password.trim())
          : '';
      return await SupabaseConfig.client.rpc(
        'admin_upsert_guard',
        params: {
          'p_token': token,
          'p_full_name': SecurityService.sanitizeInput(fullName),
          'p_password_hash': hash,
          'p_installation_id': installationId,
          'p_id': id,
        },
      ) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteGuardProfile(String id) async {
    final token = await SessionService.getToken();
    if (token == null) return false;
    try {
      return await SupabaseConfig.client.rpc(
        'admin_delete_guard',
        params: {'p_token': token, 'p_id': id},
      ) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getGuardProfiles() async {
    final token = await SessionService.getToken();
    if (token == null) return [];
    try {
      final result = await SupabaseConfig.client.rpc('admin_guards', params: {'p_token': token});
      return List<Map<String, dynamic>>.from(result as List<dynamic>);
    } catch (_) {
      return [];
    }
  }
}
