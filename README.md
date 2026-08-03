# rondas

Sistema de Control de Rondas de Seguridad Móvil (Flutter Web / Android APK).

## Configuración

Las credenciales de Supabase se leen de `.env` (no versionado) vía `--dart-define-from-file`. Compilar/ejecutar con:

```
flutter run --dart-define-from-file=.env
flutter build web --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
```

Para release (APK + web) usar `tool/build_release.sh`: compila con el flag
correcto siempre. Compilar sin `--dart-define-from-file=.env` produce un APK
que compila y firma bien pero se cierra solo al abrir (URL/key de Supabase
quedan vacías).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
