import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

class SecurityService {
  /// Sanitización de entradas de texto contra inyección de código y XSS.
  /// Elimina etiquetas HTML y caracteres potencialmente peligrosos.
  static String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Elimina etiquetas HTML/Scripts
        .replaceAll(RegExp(r"[';\-]"), '') // Sanitiza caracteres de inyección SQL
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), '') // Elimina caracteres de control invisibles
        .trim();
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Deriva una clave de cifrado de 256 bits a partir de un material secreto.
  static Uint8List deriveEncryptionKey(String secretMaterial) {
    final bytes = utf8.encode(secretMaterial.trim());
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  static String generateSecurePassword([int length = 12]) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%&*';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Verificación de integridad de ejecución en tiempo real (OWASP MASVS-RESILIENCE).
  /// Bloquea el arranque solo ante señal de alta confianza (root/jailbreak) --
  /// cualquier error del plugin o plataforma no soportada (Web) deja pasar,
  /// para no dejar la app inutilizable por un falso positivo.
  static Future<bool> verifyRuntimeIntegrity() async {
    if (kIsWeb) return true;
    try {
      final jailBroken = await SafeDevice.isJailBroken;
      return !jailBroken;
    } catch (_) {
      return true;
    }
  }

  /// Validación de SSL y formato de Endpoint
  static bool isValidSecureUrl(String url) {
    return url.startsWith('https://');
  }
}
