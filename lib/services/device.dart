import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Erkennt Fernseher (Android TV, Google TV, Fire TV) über die Android-Seite.
/// Zum Ausprobieren am Mac: `flutter run --dart-define=FORCE_TV=true`.
Future<bool> detectTelevision() async {
  if (const bool.fromEnvironment('FORCE_TV')) return true;
  if (kIsWeb || !Platform.isAndroid) return false;
  try {
    return await const MethodChannel('pulse_media/device').invokeMethod<bool>('isTelevision') ?? false;
  } on PlatformException {
    return false;
  }
}
