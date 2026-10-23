#!/bin/sh
# Baut IpFlix für LG-Fernseher (webOS) als .ipk nach dist/.
# Voraussetzung: npm install -g @webos-tools/cli
# Installieren: ares-install -d <tv> dist/com.enesyazici.ipflix_*.ipk
set -e
cd "$(dirname "$0")/.."

flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
  --dart-define=WEBOS=true --dart-define=FORCE_TV=true

STAGE=build/webos
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
cp -R webos/app "$STAGE/app"
cp -R webos/service "$STAGE/service"
cp -R build/web "$STAGE/service/www"
# Nur die CanvasKit-Variante für Chromium wird gebraucht; Wasm-Dateien raus.
rm -rf "$STAGE/service/www/canvaskit/skwasm"* "$STAGE/service/www/flutter_service_worker.js"

ares-package "$STAGE/app" "$STAGE/service" -o dist
ls -lh dist/*.ipk
