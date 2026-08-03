import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Sube fotos (incidentes, confirmación de alerta) a Supabase Storage en vez
/// de guardarlas como Base64 en una columna `text` -- no infla las tablas y
/// permite servir las imágenes vía CDN.
class StorageService {
  static const String bucket = 'incident-photos';

  /// Sube la foto y devuelve una URL firmada de larga duración.
  ///
  /// El bucket es privado: `getPublicUrl` ya no resuelve. Antes era público, y
  /// eso dejaba las fotos de incidentes descargables por cualquiera que tuviera
  /// la URL, sin credencial alguna.
  static Future<String?> uploadPhoto(Uint8List bytes, String folder) async {
    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}.jpg';
      await SupabaseConfig.client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      // 10 años: el incidente queda como evidencia y el supervisor tiene que
      // poder abrirlo mucho después de registrado.
      return await SupabaseConfig.client.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60 * 24 * 365 * 10);
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
