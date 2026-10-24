#!/bin/sh
# Reproduzierbare Release-Dateien; Zugangsdaten und persönliche Metadaten fehlen.
set -eu
cd "$(dirname "$0")/.."
target=${1:?Ziel browser, webos oder macos angeben}
release_version=${2:?Versionsnummer angeben}
build_number=${3:?Build-Nummer angeben}
python3 - "$release_version" "$build_number" <<'PY'
import re, sys
if not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]) or not sys.argv[2].isdigit():
    raise SystemExit("Ungültige Release-Version oder Build-Nummer")
PY
mkdir -p dist
case "$target" in
  browser)
    python3 scripts/package_browser.py "$release_version" "$build_number"
    ;;
  webos)
    INCLUDE_PERSONAL_IMDB=0 RELEASE_VERSION="$release_version" sh scripts/build_webos.sh
    ;;
  macos)
    if [ "$(uname -s)" != "Darwin" ]; then
      echo "Der Mac-Build benötigt macOS und vollständiges Xcode." >&2
      exit 1
    fi
    # Flutter reicht FLUTTER_XCODE_* als Xcode-Build-Einstellungen weiter.
    # Keine private Signatur und keine dauerhafte Änderung der Projektdateien.
    FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO \
    FLUTTER_XCODE_CODE_SIGNING_REQUIRED=NO \
    FLUTTER_XCODE_DEVELOPMENT_TEAM= \
    FLUTTER_XCODE_CODE_SIGN_IDENTITY=- \
      flutter build macos --release --build-name="$release_version" --build-number="$build_number"
    app=build/macos/Build/Products/Release/IpFlix.app
    test -d "$app"
    codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$app"
    codesign --verify --deep --strict "$app"
    architectures=$(lipo -archs "$app/Contents/MacOS/IpFlix")
    case "$architectures" in
      *arm64*x86_64*|*x86_64*arm64*) architecture=universal ;;
      arm64) architecture=arm64 ;;
      x86_64) architecture=x86_64 ;;
      *) echo "Unerwartete Mac-Architektur: $architectures" >&2; exit 1 ;;
    esac
    ditto -c -k --sequesterRsrc --keepParent "$app" "dist/IpFlix-macOS-$architecture-v$release_version.zip"
    ;;
  *) echo "Unbekanntes Ziel: $target" >&2; exit 1 ;;
esac
