import 'package:flutter/material.dart';

/// Paleta central de la app (tema oscuro). Antes estos hex vivían repetidos
/// como literales en cada vista — un solo lugar para cambiarlos.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color surfaceAlt = Color(0xFF111827);
  static const Color border = Color(0xFF334155);

  static const Color accent = Color(0xFF38BDF8);
  static const Color accentStrong = Color(0xFF0EA5E9);
  static const Color primaryAction = Color(0xFF0284C7);

  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textSubtle = Color(0xFF64748B);
}
