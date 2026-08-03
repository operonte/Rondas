import 'package:flutter_test/flutter_test.dart';
import 'package:rondas/services/security_service.dart';

void main() {
  group('SecurityService.sanitizeInput', () {
    test('elimina etiquetas HTML/script', () {
      expect(SecurityService.sanitizeInput('<script>alert(1)</script>hola'), 'alert(1)hola');
    });

    test('elimina comillas, guiones y punto y coma (no paréntesis)', () {
      // Documenta el comportamiento real: es un filtro parcial (blacklist),
      // no reemplaza usar siempre queries parametrizadas del lado del server.
      expect(SecurityService.sanitizeInput("Robert'); DROP TABLE--"), 'Robert) DROP TABLE');
    });

    test('recorta espacios en los bordes', () {
      expect(SecurityService.sanitizeInput('   hola mundo   '), 'hola mundo');
    });
  });

  group('SecurityService.hashPassword', () {
    test('es determinístico para la misma entrada', () {
      expect(SecurityService.hashPassword('clave123'), SecurityService.hashPassword('clave123'));
    });

    test('produce un hash SHA-256 de 64 caracteres hex', () {
      final hash = SecurityService.hashPassword('clave123');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('recorta espacios antes de hashear (mismo hash con o sin espacios)', () {
      expect(SecurityService.hashPassword('clave123'), SecurityService.hashPassword('  clave123  '));
    });

    test('entradas distintas producen hashes distintos', () {
      expect(SecurityService.hashPassword('clave123'), isNot(SecurityService.hashPassword('clave124')));
    });
  });

  group('SecurityService.deriveEncryptionKey', () {
    test('deriva una clave de 32 bytes (256 bits)', () {
      expect(SecurityService.deriveEncryptionKey('material-secreto').length, 32);
    });
  });

  group('SecurityService.generateSecurePassword', () {
    test('respeta la longitud pedida', () {
      expect(SecurityService.generateSecurePassword(20).length, 20);
    });

    test('usa el largo por defecto de 12 si no se especifica', () {
      expect(SecurityService.generateSecurePassword().length, 12);
    });

    test('no genera la misma password dos veces seguidas (con altísima probabilidad)', () {
      expect(SecurityService.generateSecurePassword(), isNot(SecurityService.generateSecurePassword()));
    });
  });

  group('SecurityService.isValidSecureUrl', () {
    test('acepta https', () {
      expect(SecurityService.isValidSecureUrl('https://ejemplo.supabase.co'), isTrue);
    });

    test('rechaza http sin cifrar', () {
      expect(SecurityService.isValidSecureUrl('http://ejemplo.supabase.co'), isFalse);
    });

    test('rechaza URLs vacías o mal formadas', () {
      expect(SecurityService.isValidSecureUrl(''), isFalse);
      expect(SecurityService.isValidSecureUrl('ftp://ejemplo.com'), isFalse);
    });
  });
}
