import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/security_service.dart';

class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> init() async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw ArgumentError(
        'Faltan SUPABASE_URL / SUPABASE_ANON_KEY. '
        'Compila con --dart-define-from-file=.env (o --dart-define individuales).',
      );
    }
    if (!SecurityService.isValidSecureUrl(supabaseUrl)) {
      throw ArgumentError('La URL de Supabase debe usar https://');
    }

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      debug: false,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
