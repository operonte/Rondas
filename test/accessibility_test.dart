import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rondas/views/login_view.dart';

/// Envuelve una vista simulando un tamaño de pantalla y escala de texto dados.
Widget _harness(Widget child, {required double textScale, required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: child,
    ),
  );
}

void main() {
  group('Accesibilidad - escalado de texto en LoginView', () {
    // Un guardia con baja visión sube el tamaño de fuente del sistema; la
    // pantalla de login no debe romperse ni recortar contenido.
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('renderiza sin overflow con escala ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_harness(
          const LoginView(),
          textScale: scale,
          size: const Size(360, 640),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en pantalla angosta y escala grande sigue sin romperse', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        const LoginView(),
        textScale: 2.0,
        size: const Size(320, 568),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Accesibilidad - etiquetas semánticas', () {
    testWidgets('los campos de login son alcanzables por lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness(
        const LoginView(),
        textScale: 1.0,
        size: const Size(360, 640),
      ));
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp('Contraseña de Acceso')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('INGRESAR AL SISTEMA')), findsWidgets);

      handle.dispose();
    });
  });
}
