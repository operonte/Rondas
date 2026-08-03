import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  bool _scanned = false;
  String? _error;

  void _handleBarcode(BarcodeCapture capture) {
    if (_scanned || capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _scanned = true;
    String location = rawValue;
    try {
      final payload = jsonDecode(rawValue);
      if (payload is Map<String, dynamic> && payload.containsKey('location')) {
        location = payload['location']?.toString() ?? rawValue;
      }
    } catch (_) {
      // Ignorar si no es JSON válido.
    }

    if (!mounted) return;
    Navigator.of(context).pop({'location': location, 'scan_type': 'qr'});
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escáner QR')),
        body: const Center(child: Text('Escaneo QR no disponible en Web.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Escanear Código QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _handleBarcode,
          ),
          if (_error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black87,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              color: Colors.black54,
              child: const Text(
                'Apunta al código QR. El escáner se cerrará automáticamente al detectar un código válido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
