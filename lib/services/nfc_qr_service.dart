import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../views/qr_scanner_view.dart';

class NfcQrService {
  static bool get isSupported => !kIsWeb;

  static Future<bool> get nfcAvailable async {
    if (kIsWeb) return false;
    try {
      return await FlutterNfcKit.nfcAvailability == NFCAvailability.available;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>?> scanNFC() async {
    if (!await nfcAvailable) {
      return null;
    }

    try {
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 20));
      final location = tag.id;
      String scanLocation = location.isEmpty ? 'Punto de control NFC' : location;

      if (tag.ndefAvailable == true) {
        final records = await FlutterNfcKit.readNDEFRecords();
        for (final record in records) {
          final payload = record.payload;
          if (payload != null && payload.isNotEmpty) {
            final text = String.fromCharCodes(payload);
            if (text.isNotEmpty) {
              scanLocation = text;
              break;
            }
          }
        }
      }

      return {
        'location': scanLocation,
        'scan_type': 'checkin_nfc',
        'tag_id': location,
      };
    } catch (_) {
      return null;
    } finally {
      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'Lectura NFC finalizada');
      } catch (_) {
        // Ignore finish errors when polling was not active.
      }
    }
  }

  static Future<Map<String, String>?> scanQR(NavigatorState navigator) async {
    if (!isSupported) {
      return null;
    }

    final result = await navigator.push<Map<String, String>?>(
      MaterialPageRoute(builder: (_) => const QrScannerView()),
    );
    if (result != null) {
      return {
        ...result,
        'scan_type': 'checkin_qr',
      };
    }
    return null;
  }
}
