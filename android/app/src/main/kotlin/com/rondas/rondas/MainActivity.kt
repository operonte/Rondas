package com.rondas.rondas

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE: bloquea capturas de pantalla y deja en blanco la vista
        // previa de la app en la lista de recientes.
        //
        // El panel del supervisor muestra los códigos de acceso de todas las
        // instalaciones y la ubicación en tiempo real de los guardias. Sin
        // esto, esa información queda en cualquier captura y en la miniatura
        // que el sistema guarda al cambiar de app, visible para quien tome el
        // teléfono desbloqueado.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
