// Direkter Zugriff auf libmpv. Im Browser (webOS) gibt es kein libmpv;
// dort sind die Aufrufe wirkungslos und Eigenschaften unbekannt.
export 'mpv_bridge_native.dart' if (dart.library.js_interop) 'mpv_bridge_web.dart';
