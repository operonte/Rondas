# Reglas de ProGuard/R8 para el build de release.
# El código Dart se ofusca aparte con `flutter build apk --obfuscate`; esto
# cubre la capa Java/Kotlin (Flutter embedding y plugins nativos).

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

# Conservar anotaciones y firmas genéricas: sin esto fallan deserializaciones
# y algunos plugins que inspeccionan tipos en runtime.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
