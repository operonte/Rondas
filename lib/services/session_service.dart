import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda el token de sesión emitido por la función `login` de Supabase.
///
/// Todas las operaciones contra la base pasan por funciones RPC que exigen
/// este token: las tablas no aceptan consultas directas con la anon key
/// (ver `supabase/security_sessions.sql`). El token equivale a una sesión
/// abierta, así que se guarda en el almacén cifrado del sistema (Keystore en
/// Android) y no en SharedPreferences, que en un dispositivo rooteado se lee
/// en texto plano.
class SessionService {
  static const String _tokenKey = 'rondas_session_token';
  static const _secure = FlutterSecureStorage();
  static String? _cached;

  /// En Web no hay Keystore; flutter_secure_storage cae a almacenamiento del
  /// navegador, que no aporta cifrado real. Se acepta ahí y se usa el almacén
  /// seguro en móvil, que es donde corre la app de los guardias.
  static bool get _useSecure => !kIsWeb;

  static Future<String?> getToken() async {
    if (_cached != null) return _cached;
    try {
      if (_useSecure) {
        _cached = await _secure.read(key: _tokenKey);
      } else {
        final prefs = await SharedPreferences.getInstance();
        _cached = prefs.getString(_tokenKey);
      }
    } catch (_) {
      // Si el almacén seguro falla (dispositivo sin Keystore utilizable), se
      // trata como sesión ausente: la app pide iniciar sesión de nuevo.
      _cached = null;
    }
    return _cached;
  }

  static Future<void> setToken(String token) async {
    _cached = token;
    try {
      if (_useSecure) {
        await _secure.write(key: _tokenKey, value: token);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cached = null;
    try {
      if (_useSecure) {
        await _secure.delete(key: _tokenKey);
      }
      // Se limpia también la copia en SharedPreferences: versiones anteriores
      // guardaban el token ahí y quedaría accesible tras cerrar sesión.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}
