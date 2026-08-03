# Reglas de ProGuard/R8 para el build de release.
# Solo R8/ProGuard cubre la capa Java/Kotlin (embedding + plugins nativos).
# NO se usa --obfuscate Dart: la doble ofuscación rompe plugins nativos.

# Flutter embedding: se referencia por reflexión desde el runtime nativo.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Plugins que usan reflexión o JNI y se rompen si R8 los renombra.
-keep class com.baseflow.geolocator.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class io.flutter.plugins.camera.** { *; }

# NFC (flutter_nfc_kit) usa clases de la plataforma vía reflexión.
-keep class im.nfc.** { *; }
-dontwarn im.nfc.**

# mobile_scanner depende de ML Kit; sus modelos se resuelven en runtime.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Supabase / Realtime / Postgrest: usan reflexión para deserializar JSON.
-keep class io.supabase.** { *; }
-keep class com.supabase.** { *; }
-dontwarn io.supabase.**

# Hive: abre archivos binarios por tipo; falla si R8 renombra las clases.
-keep class com.hivedb.** { *; }
-keep class ** extends com.google.flatbuffers.Table { *; }

# flutter_secure_storage: usa KeyStore de Android por nombre de clase.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# audioplayers: usa MediaPlayer/ExoPlayer por reflexión en algunos paths.
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# Connectivity Plus / Battery Plus.
-keep class com.baseflow.connectivity.** { *; }
-keep class com.baseflow.battery.** { *; }

# url_launcher.
-keep class io.flutter.plugins.urllauncher.** { *; }

# image_picker / file provider.
-keep class io.flutter.plugins.imagepicker.** { *; }

# Conservar anotaciones y firmas genéricas: sin esto fallan deserializaciones
# y algunos plugins que inspeccionan tipos en runtime.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Evitar que R8 elimine clases anónimas y lambdas usadas en callbacks nativos.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepclasseswithmembernames class * {
    native <methods>;
}
