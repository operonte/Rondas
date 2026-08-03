#!/usr/bin/env bash
# Compila APK y web de release con las credenciales de Supabase embebidas.
#
# Sin --dart-define-from-file=.env, SupabaseConfig.init() recibe URL/key
# vacías y lanza un ArgumentError sin capturar en main() antes de runApp():
# la app compila y firma sin errores pero se cierra sola al abrir. Ya pasó
# dos veces por compilar a mano con "flutter build apk --release" solo.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Falta .env (SUPABASE_URL / SUPABASE_ANON_KEY) en la raíz del proyecto." >&2
  exit 1
fi

flutter build apk --release --dart-define-from-file=.env
flutter build web --release --dart-define-from-file=.env

echo "APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Web: build/web"
