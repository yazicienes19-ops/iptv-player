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
# Die Release-Pipeline setzt die tatsächliche Tag-Version nur im Bauverzeichnis.
if [ -n "${RELEASE_VERSION:-}" ]; then
  python3 - "$STAGE" "$RELEASE_VERSION" <<'PY'
import json
from pathlib import Path
import re
import sys
stage, version = Path(sys.argv[1]), sys.argv[2]
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Ungültige Release-Version")
for file in (stage / "app/appinfo.json", stage / "service/package.json"):
    data = json.loads(file.read_text())
    data["version"] = version
    file.write_text(json.dumps(data, indent=2) + "\n")
PY
fi
# Persönliche IMDb-Daten gehören nicht automatisch in ein verteilbares Paket.
# Für die eigene lokale Installation bewusst mit INCLUDE_PERSONAL_IMDB=1 bauen.
if [ "${INCLUDE_PERSONAL_IMDB:-0}" != "1" ]; then
  rm -f "$STAGE/service/www/data/imdb.json"
fi
# Aktuelle Stammzertifikate für das alte Node auf dem Fernseher.
if [ -f /etc/ssl/cert.pem ]; then
  cp /etc/ssl/cert.pem "$STAGE/service/cacert.pem"
elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  cp /etc/ssl/certs/ca-certificates.crt "$STAGE/service/cacert.pem"
else
  echo "Kein Stammzertifikat-Bündel gefunden." >&2
  exit 1
fi

ares-package "$STAGE/app" "$STAGE/service" -o dist
ls -lh dist/*.ipk
