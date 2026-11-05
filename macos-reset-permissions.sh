#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/RustDesk.app"
DAEMON_PLIST="/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
AGENT_PLIST="/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
INPUT_ARG="${1:-}"

BUNDLE_IDS=(
  "com.carriez.rustdesk"
  "com.carriez.RustDesk"
  "com.carriez.RustDesk_service"
  "com.carriez.RustDesk_server"
  "com.carriez.flutterHbb"
)

TCC_SERVICES=(
  "All"
  "Accessibility"
  "ScreenCapture"
  "ListenEvent"
  "PostEvent"
)

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Fehler: Dieses Skript ist nur für macOS gedacht." >&2
  exit 1
fi

echo "==> 1. Prüfe Sudo-Rechte..."
sudo -v

# Suche nach DMG: entweder als Argument übergeben oder die neueste rustdesk*.dmg in ~/Downloads
DMG_PATH=""
if [[ -n "$INPUT_ARG" && "$INPUT_ARG" == *.dmg && -f "$INPUT_ARG" ]]; then
  DMG_PATH="$INPUT_ARG"
elif [[ -n "$INPUT_ARG" && "$INPUT_ARG" == *.app && -d "$INPUT_ARG" ]]; then
  APP_PATH="$INPUT_ARG"
else
  LATEST_DMG="$(ls -t "$HOME"/Downloads/[rR]ust[dD]esk*.dmg 2>/dev/null | head -n 1 || true)"
  if [[ -n "$LATEST_DMG" && -f "$LATEST_DMG" ]]; then
    DMG_PATH="$LATEST_DMG"
  fi
fi

echo "==> 2. Stoppe laufende RustDesk-Dienste und Prozesse..."
CURRENT_UID="$(id -u)"
if [[ -f "$AGENT_PLIST" ]]; then
  launchctl bootout "gui/$CURRENT_UID" "$AGENT_PLIST" 2>/dev/null || \
    launchctl unload -w "$AGENT_PLIST" 2>/dev/null || true
fi
if [[ -f "$DAEMON_PLIST" ]]; then
  sudo launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || \
    sudo launchctl unload -w "$DAEMON_PLIST" 2>/dev/null || true
fi
sudo killall -9 RustDesk 2>/dev/null || true

if [[ -n "$DMG_PATH" ]]; then
  echo "==> 3. Installiere RustDesk aus DMG: $DMG_PATH"
  sudo xattr -rd com.apple.quarantine "$DMG_PATH" 2>/dev/null || true
  sudo xattr -cr "$DMG_PATH" 2>/dev/null || true

  MOUNT_DIR="$(mktemp -d /tmp/rustdesk_dmg.XXXXXX)"
  cleanup_dmg() {
    /usr/bin/hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  }
  trap cleanup_dmg EXIT

  echo "    Mounte DMG..."
  /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null

  if [[ ! -d "$MOUNT_DIR/RustDesk.app" ]]; then
    echo "Fehler: RustDesk.app wurde im DMG ($DMG_PATH) nicht gefunden." >&2
    exit 1
  fi

  echo "    Kopiere RustDesk.app nach $APP_PATH..."
  sudo rm -rf "$APP_PATH"
  sudo /usr/bin/ditto "$MOUNT_DIR/RustDesk.app" "$APP_PATH"

  echo "    Unmounting DMG..."
  cleanup_dmg
  trap - EXIT
else
  echo "==> 3. Keine DMG in ~/Downloads gefunden – verwende vorhandenes $APP_PATH"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Fehler: $APP_PATH wurde nicht gefunden und keine DMG lag in ~/Downloads." >&2
  exit 1
fi

echo "==> 4. Entferne Gatekeeper-Quarantäne & mache $APP_PATH vertrauenswürdig..."
sudo chown -R root:wheel "$APP_PATH"
sudo chmod -R go-w "$APP_PATH"
sudo xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true
sudo xattr -cr "$APP_PATH" 2>/dev/null || true

echo "==> 5. Erneuere konsistente Ad-hoc-Signatur für App und eingebettete Binaries..."
sudo codesign --force --deep --sign - "$APP_PATH"

echo "==> 6. Setze macOS TCC-Berechtigungen (Bedienungshilfen, Bildschirmaufnahme, Eingabeüberwachung) zurück..."
for bid in "${BUNDLE_IDS[@]}"; do
  for svc in "${TCC_SERVICES[@]}"; do
    tccutil reset "$svc" "$bid" 2>/dev/null || true
    sudo tccutil reset "$svc" "$bid" 2>/dev/null || true
  done
done

echo "==> 7. Starte RustDesk-Dienste neu..."
if [[ -f "$DAEMON_PLIST" ]]; then
  sudo launchctl bootstrap system "$DAEMON_PLIST" 2>/dev/null || \
    sudo launchctl load -w "$DAEMON_PLIST" 2>/dev/null || true
fi
if [[ -f "$AGENT_PLIST" ]]; then
  launchctl bootstrap "gui/$CURRENT_UID" "$AGENT_PLIST" 2>/dev/null || \
    launchctl load -w "$AGENT_PLIST" 2>/dev/null || true
fi

echo "==> 8. Öffne RustDesk und die macOS-Systemeinstellungen (Bedienungshilfen)..."
open "$APP_PATH" || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo ""
echo "Fertig! RustDesk wurde installiert, signiert und alle alten Berechtigungen wurden zurückgesetzt."
echo "Bitte aktiviere RustDesk jetzt in den geöffneten Systemeinstellungen unter:"
echo "  - Bedienungshilfen (Accessibility)"
echo "  - Bildschirmaufnahme (Screen Recording)"
echo "  - Eingabeüberwachung (Input Monitoring, falls angefragt)"
