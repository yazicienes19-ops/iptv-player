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
    # Mit dem Apple-Development-Zertifikat (GitHub-Secret) signieren: Der Schlüsselbund
    # erkennt jede neue Version über die Team-ID als dieselbe App und fragt nicht erneut.
    # Ohne Secret (z. B. Pull Requests) bleibt es bei einer Ad-hoc-Signatur.
    if [ -n "${MACOS_SIGNING_P12:-}" ]; then
      keychain="${RUNNER_TEMP:-/tmp}/ipflix-signing.keychain-db"
      keychain_password=$(openssl rand -hex 16)
      original_keychains=$(security list-keychains -d user | tr -d '"' | xargs)
      cleanup_keychain() {
        # shellcheck disable=SC2086
        security list-keychains -d user -s $original_keychains || true
        security delete-keychain "$keychain" 2>/dev/null || true
        rm -f "${RUNNER_TEMP:-/tmp}/ipflix-signing.p12"
      }
      trap cleanup_keychain EXIT
      printf '%s' "$MACOS_SIGNING_P12" | base64 --decode > "${RUNNER_TEMP:-/tmp}/ipflix-signing.p12"
      security create-keychain -p "$keychain_password" "$keychain"
      security set-keychain-settings -lut 3600 "$keychain"
      security unlock-keychain -p "$keychain_password" "$keychain"
      security import "${RUNNER_TEMP:-/tmp}/ipflix-signing.p12" -k "$keychain" \
        -P "$MACOS_SIGNING_PASSWORD" -T /usr/bin/codesign >/dev/null
      security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
      # Öffentliches Apple-Zwischenzertifikat, damit codesign die Kette sicher bilden kann.
      security import scripts/certs/AppleWWDRCAG3.pem -k "$keychain" >/dev/null || true
      # shellcheck disable=SC2086
      security list-keychains -d user -s "$keychain" $original_keychains
      # Erste Signier-Identität aus dem Secret (Apple Development mit Team-ID).
      identity=$(security find-identity -p codesigning "$keychain" | awk '/[0-9A-F]{40}/ {print $2; exit}')
      test -n "$identity"
      codesign --force --deep --keychain "$keychain" --sign "$identity" \
        --entitlements macos/Runner/Release.entitlements "$app"
      # Der Schlüsselbund vertraut den Einträgen über die Team-ID; ohne sie fragt er nach jedem Update.
      team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
      if [ -z "$team" ] || [ "$team" = "not set" ]; then
        echo "Signatur ohne Team-ID, der Schlüsselbund würde nach jedem Update fragen." >&2
        exit 1
      fi
      echo "Signiert mit Team $team"
    else
      codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$app"
    fi
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
