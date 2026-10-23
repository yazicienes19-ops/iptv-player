#!/bin/sh
# Baut IpFlix für LG-Fernseher (webOS) als .ipk nach dist/.
# Die Oberfläche ist webos/tv (reines JavaScript für Chrome 53 / webOS 4),
# nicht die Flutter-App: Flutter braucht WebAssembly, das webOS 4 fehlt.
# Voraussetzung: npm install -g @webos-tools/cli
# Installieren: ares-install -d tv dist/com.enesyazici.ipflix_*.ipk
set -e
cd "$(dirname "$0")/.."

STAGE=build/webos
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
cp -R webos/app "$STAGE/app"
cp -R webos/service "$STAGE/service"
cp -R webos/tv "$STAGE/service/www"
# Aktuelle Stammzertifikate für das alte Node auf dem Fernseher.
cp /etc/ssl/cert.pem "$STAGE/service/cacert.pem"

ares-package "$STAGE/app" "$STAGE/service" -o dist
ls -lh dist/*.ipk
