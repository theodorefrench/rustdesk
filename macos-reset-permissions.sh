#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-/Applications/RustDesk.app}"
DAEMON_PLIST="/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
AGENT_PLIST="/Library/LaunchAgents/com.carriez.RustDesk_server.plist"

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

echo "==> 2. Entferne Quarantäne-Attribute von RustDesk-DMGs in ~/Downloads (falls vorhanden)..."
shopt -s nullglob
for dmg in "$HOME"/Downloads/[rR]ust[dD]esk*.dmg; do
  echo "    Entferne Quarantäne von: $dmg"
  sudo xattr -rd com.apple.quarantine "$dmg" 2>/dev/null || true
  sudo xattr -cr "$dmg" 2>/dev/null || true
done
shopt -u nullglob

if [[ ! -d "$APP_PATH" ]]; then
  echo "Warnung: $APP_PATH wurde noch nicht gefunden."
  echo "Bitte kopiere RustDesk.app zuerst nach /Applications und führe das Skript erneut aus."
  exit 1
fi

echo "==> 3. Stoppe laufende RustDesk-Dienste und Prozesse..."
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
echo "Fertig! Bitte aktiviere RustDesk jetzt in den geöffneten Systemeinstellungen unter:"
echo "  - Bedienungshilfen (Accessibility)"
echo "  - Bildschirmaufnahme (Screen Recording)"
echo "  - Eingabeüberwachung (Input Monitoring, falls angefragt)"
