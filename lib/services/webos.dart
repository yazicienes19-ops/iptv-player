import 'package:flutter/foundation.dart';

/// Gebaut für LG-Fernseher (`--dart-define=WEBOS=true`). Der Browser auf dem
/// Fernseher sperrt Anfragen an fremde Server (CORS). Deshalb laufen alle
/// Anfragen außer dem Video selbst über den Hilfsdienst im Paket
/// (`webos/service/proxy.js`), der auch die App ausliefert.
const isWebOs = kIsWeb && bool.fromEnvironment('WEBOS');

/// Leitet eine Adresse über den Hilfsdienst; außerhalb von webOS unverändert.
/// Der User-Agent reist als Parameter mit, weil Browser den Kopf nicht setzen dürfen.
String proxiedUrl(String url, {String? userAgent}) {
  if (!isWebOs || !url.startsWith('http')) return url;
  return Uri.base.resolveUri(Uri(path: '/p', queryParameters: {'u': url, 'ua': ?userAgent})).toString();
}

/// Lebenszeichen an den Hilfsdienst: Ohne Anfragen beendet er sich nach
/// einigen Minuten, etwa wenn die App geschlossen wurde.
String get webOsPingUrl => Uri.base.resolve('/ping').toString();
