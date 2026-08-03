import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'guard_view.dart';

/// Paso posterior al login del guardia: ya sabemos quién es (entró con su
/// contraseña personal), falta saber dónde trabaja. Elige una instalación de
/// las que creó el supervisor y confirma con el código de ese sitio.
///
/// Hasta que no completa este paso, el servidor rechaza registrar GPS o
/// incidentes: una ronda sin instalación no se puede supervisar.
class InstallationPickerView extends StatefulWidget {
  final String guardName;

  const InstallationPickerView({super.key, required this.guardName});

  @override
  State<InstallationPickerView> createState() => _InstallationPickerViewState();
}

class _InstallationPickerViewState extends State<InstallationPickerView> {
  List<Map<String, dynamic>> _installations = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AuthService.getAvailableInstallations();
    if (!mounted) return;
    setState(() {
      _installations = list;
      _loading = false;
    });
  }

  Future<void> _askAccessCode(Map<String, dynamic> installation) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = installation['name']?.toString() ?? 'Instalación';

    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Escribí la contraseña de esta instalación para iniciar tu ronda acá.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Contraseña de la instalación',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.accent),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresá la contraseña' : null,
                onFieldSubmitted: (v) {
                  if (formKey.currentState!.validate()) Navigator.pop(ctx, v.trim());
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            child: const Text('ENTRAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (code == null || !mounted) return;

    setState(() => _submitting = true);
    final ok = await AuthService.enterInstallation(installation['id'].toString(), code);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña de instalación incorrecta.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GuardView()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Elegí tu instalación',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AuthService.logout();
              if (!mounted) return;
              navigator.pop();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hola, ${widget.guardName}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                        'Elegí dónde vas a hacer tu ronda. Te va a pedir la contraseña del lugar.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_submitting) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _installations.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No hay instalaciones creadas todavía.\nPedile al supervisor que cree una.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _installations.length,
                          itemBuilder: (ctx, i) {
                            final item = _installations[i];
                            final address = item['address']?.toString();
                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.business, color: AppColors.accent),
                                title: Text(item['name']?.toString() ?? 'Instalación',
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold)),
                                subtitle: (address == null || address.isEmpty)
                                    ? null
                                    : Text(address,
                                        style: const TextStyle(
                                            color: AppColors.textMuted, fontSize: 12)),
                                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                onTap: _submitting ? null : () => _askAccessCode(item),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
