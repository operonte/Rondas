import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'installation_picker_view.dart';
import 'super_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passController = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    // Un solo campo: el servidor reconoce por la contraseña si es el supervisor
    // o un guardia. El código de instalación se pide después, al elegir sitio.
    final res = await AuthService.login(password: _passController.text.trim());
    if (!mounted) return;

    if (res['success'] == true) {
      final role = res['role'] as UserRole;
      if (role == UserRole.guardia) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InstallationPickerView(
              guardName: res['name']?.toString() ?? 'Guardia',
            ),
          ),
        );
      } else if (role == UserRole.superusuario) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SuperView()));
      }
    } else {
      setState(() {
        _errorMessage = res['error'];
        _isSubmitting = false;
      });
    }
  }

  void _openPrivacyPolicy() async {
    final uri = Uri.parse('privacy.html');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, size: 64, color: AppColors.accent),
                const SizedBox(height: 12),
                const Text(
                  'CONTROL DE RONDAS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Acceso Seguro de Guardia y Supervisión',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _passController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Contraseña de Acceso',
                          labelStyle: const TextStyle(color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.background,
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.accent),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La contraseña es obligatoria';
                          }
                          if (value.trim().length < 4) {
                            return 'La contraseña debe tener al menos 4 caracteres';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ingresá tu contraseña personal. Si sos guardia, después vas a elegir la instalación donde harás la ronda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2.0)),
                        )
                      : const Text('INGRESAR AL SISTEMA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 6,
                  children: [
                    GestureDetector(
                      onTap: _openPrivacyPolicy,
                      child: const Text(
                        'Política de Privacidad',
                        style: TextStyle(color: AppColors.accent, fontSize: 12, decoration: TextDecoration.underline),
                      ),
                    ),
                    const Text(
                      'cofee.key@gmail.com',
                      style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
