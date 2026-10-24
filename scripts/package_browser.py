#!/usr/bin/env python3
"""Create the local browser release from an explicit, public-file allowlist."""
import argparse
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "webos/service/proxy.js", "webos/service/setup.js", "webos/service/setup.html",
    "webos/service/package.json", "webos/service/services.json",
    "webos/dev/start.js", "webos/dev/mock_xtream.py",
)


def package(root, output, version, build_number):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not str(build_number).isdigit():
        raise ValueError("Ungültige Version oder Build-Nummer")
    prefix = f"IpFlix-browser-v{version}/"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        paths = [root / name for name in FILES]
        # Never package imported metadata, local credentials, caches or build files.
        for path in sorted((root / "webos/tv").rglob("*")):
            relative = path.relative_to(root / "webos/tv")
            if path.is_file() and "data" not in relative.parts and not any(part.startswith(".") for part in relative.parts):
                paths.append(path)
        for path in paths:
            if path.is_symlink():
                raise ValueError(f"Symlinks sind im Browserpaket nicht erlaubt: {path.name}")
            name = path.relative_to(root).as_posix()
            if name == "webos/service/package.json":
                data = json.loads(path.read_text())
                data["version"] = version
                archive.writestr(prefix + name, json.dumps(data, indent=2) + "\n")
            else:
                archive.write(path, prefix + name)
        archive.writestr(prefix + "release-info.json", json.dumps({"version": version, "build": int(build_number)}, indent=2) + "\n")
        archive.writestr(prefix + "STARTEN.txt", f"""IpFlix {version} — lokale Browser-Version

1. Node.js 22 oder neuer und Python 3 installieren.
2. Dieses ZIP vollständig entpacken.
3. Im entpackten Ordner ein Terminal öffnen und ausführen:

   node webos/dev/start.js

4. http://127.0.0.1:47823/ im Browser öffnen.
   Testzugang: Xtream / Server http://127.0.0.1:8766 / Benutzer test / Passwort test

Strg+C beendet die Vorschau. Für lokale Testvideos kann optional ffmpeg
installiert werden; sonst wird ein freier Internet-Testclip verwendet.
Die Demo enthält keine echten Spielfilme. Eine eigene Playlist kann in der
Anmeldung verwendet werden. Videounterstützung hängt vom Browser ab.

Dieses Paket benötigt den lokalen Dienst; HTML allein auf einen Webserver
hochzuladen reicht nicht. Zugangsdaten und Verlauf bleiben im Browserprofil.
Der persönliche IMDb-Katalog ist nicht enthalten. Die Empfehlungen können
vorhandene Anbieter-Metadaten nutzen. Weitere Hinweise und alle Versionen:
https://github.com/yazicienes19-ops/iptv-player
https://github.com/yazicienes19-ops/iptv-player/releases
""")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("build_number")
    args = parser.parse_args()
    print(package(ROOT, ROOT / "dist" / f"IpFlix-browser-v{args.version}.zip", args.version, args.build_number))
