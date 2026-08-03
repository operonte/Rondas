import 'package:flutter/material.dart';
import 'config/supabase_config.dart';
import 'services/offline_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/security_service.dart';
import 'theme/app_colors.dart';
import 'views/login_view.dart';
import 'views/guard_view.dart';
import 'views/installation_picker_view.dart';
import 'views/super_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verificación de integridad en tiempo de ejecución (OWASP MASVS)
  if (!await SecurityService.verifyRuntimeIntegrity()) {
    runApp(const _CompromisedDeviceApp());
    return; // Cancela inicio si el entorno está adulterado (root/jailbreak)
  }

  await SupabaseConfig.init();
  await NotificationService.init();
  await OfflineService.init();

  final initialRole = await AuthService.getCurrentRole();
  // Un guardia con sesión pero sin instalación elegida (cerró la app en ese
  // paso) tiene que volver al selector: sin instalación el servidor rechaza
  // registrar la ronda.
  final needsInstallation = initialRole == UserRole.guardia &&
      await AuthService.getCurrentInstallationId() == null;
  final guardName = needsInstallation ? await AuthService.getCurrentUserName() : '';

  runApp(RondasApp(
    initialRole: initialRole,
    needsInstallation: needsInstallation,
    guardName: guardName,
  ));
}

class RondasApp extends StatelessWidget {
  final UserRole initialRole;
  final bool needsInstallation;
  final String guardName;

  const RondasApp({
    super.key,
    required this.initialRole,
    this.needsInstallation = false,
    this.guardName = '',
  });

  @override
  Widget build(BuildContext context) {
    Widget homeWidget;
    switch (initialRole) {
      case UserRole.guardia:
        homeWidget = needsInstallation
            ? InstallationPickerView(guardName: guardName)
            : const GuardView();
        break;
      case UserRole.superusuario:
        homeWidget = const SuperView();
        break;
      case UserRole.none:
        homeWidget = const LoginView();
        break;
    }

    return MaterialApp(
      title: 'Control de Rondas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
      ),
      home: homeWidget,
    );
  }
}

/// Pantalla mostrada cuando `verifyRuntimeIntegrity` detecta root/jailbreak.
/// Antes la app quedaba en blanco sin explicación; esto al menos le dice
/// al guardia por qué no puede entrar en vez de parecer un cuelgue.
class _CompromisedDeviceApp extends StatelessWidget {
  const _CompromisedDeviceApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_bad_outlined, size: 64, color: Colors.redAccent),
                SizedBox(height: 16),
                Text(
                  'No se puede iniciar la aplicación',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Se detectó que este dispositivo está rooteado/jailbreak. '
                  'Por seguridad, Control de Rondas no funciona en dispositivos modificados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
