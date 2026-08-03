import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Sube fotos (incidentes, confirmación de alerta) a Supabase Storage en vez
/// de guardarlas como Base64 en una columna `text` -- no infla las tablas y
/// permite servir las imágenes vía CDN.
class StorageService {
  static const String bucket = 'incident-photos';

  /// Sube la foto y devuelve su **ruta** dentro del bucket, no una URL.
  ///
  /// Guardar una URL firmada a diez años equivalía a dejarla pública: si esa
  /// dirección se filtraba, servía para siempre. Ahora se guarda la ruta y la
  /// URL se firma al momento de mostrarla, con vencimiento corto.
  static Future<String?> uploadPhoto(Uint8List bytes, String folder) async {
    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}.jpg';
      await SupabaseConfig.client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Firma una ruta para poder mostrarla. Una hora alcanza para abrir el
  /// incidente y deja la dirección inservible poco después.
  ///
  /// Acepta también URLs completas de versiones anteriores, que guardaban la
  /// URL firmada en lugar de la ruta.
  static Future<String?> signedUrlFor(String pathOrUrl) async {
    if (pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    try {
      return await SupabaseConfig.client.storage
          .from(bucket)
          .createSignedUrl(pathOrUrl, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  static String _randomSuffix() {
    final rnd = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
