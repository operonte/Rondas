import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rondas/services/auth_service.dart';
import 'package:rondas/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionService.clear();
  });

  group('SessionService', () {
    test('sin token guardado devuelve null', () async {
      expect(await SessionService.getToken(), isNull);
    });

    test('guarda y recupera el token', () async {
      await SessionService.setToken('abc-123');
      expect(await SessionService.getToken(), 'abc-123');
    });

    test('clear elimina el token', () async {
      await SessionService.setToken('abc-123');
      await SessionService.clear();
      expect(await SessionService.getToken(), isNull);
    });
  });

  group('AuthService - sesión local', () {
    test('sin sesión iniciada, el rol es none', () async {
      expect(await AuthService.getCurrentRole(), UserRole.none);
      expect(await AuthService.getCurrentUserId(), isNull);
    });

    // El rol vive en SharedPreferences, pero sin token la sesión no sirve para
    // nada: el servidor rechaza toda operación. getCurrentRole lo refleja para
    // que la app mande al login en vez de mostrar un panel inutilizable.
    test('con rol guardado pero sin token, el rol sigue siendo none', () async {
      SharedPreferences.setMockInitialValues({'rondas_user_role': 'superusuario'});
      expect(await AuthService.getCurrentRole(), UserRole.none);
    });

    test('con rol y token, devuelve el rol guardado', () async {
      SharedPreferences.setMockInitialValues({'rondas_user_role': 'superusuario'});
      await SessionService.setToken('token-valido');
      expect(await AuthService.getCurrentRole(), UserRole.superusuario);
    });

    test('rol guardia con token se reconoce', () async {
      SharedPreferences.setMockInitialValues({'rondas_user_role': 'guardia'});
      await SessionService.setToken('token-valido');
      expect(await AuthService.getCurrentRole(), UserRole.guardia);
    });

    test('logout limpia token y datos de sesión aunque no haya red', () async {
      SharedPreferences.setMockInitialValues({
        'rondas_user_role': 'guardia',
        'rondas_user_id': 'guard-1',
        'rondas_user_name': 'Guardia - Juan Pérez',
        'rondas_inst_name': 'Sucursal Centro',
        'rondas_inst_id': 'inst-1',
      });
      await SessionService.setToken('token-valido');

      await AuthService.logout();

      expect(await SessionService.getToken(), isNull);
      expect(await AuthService.getCurrentRole(), UserRole.none);
      expect(await AuthService.getCurrentUserId(), isNull);
      expect(await AuthService.getCurrentInstallationId(), isNull);
      expect(await AuthService.getInstallationName(), 'Instalación');
      expect(await AuthService.getCurrentUserName(), 'Usuario');
    });

    test('sin token, las operaciones de superusuario fallan sin llamar al servidor', () async {
      expect(await AuthService.getGuardProfiles(), isEmpty);
      expect(await AuthService.isGuardNameAvailable('Alguien'), isFalse);
      expect(await AuthService.deleteGuardProfile('id'), isFalse);
      expect(await AuthService.updateSuperuserPassword('a', 'b'), isFalse);
    });
  });
}
