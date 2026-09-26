#!/usr/bin/env bash
# Mini-PC release-sync: haalt elke release van GitHub en werkt site + downloads bij.
# Draait op de Mini-PC via systemd-timer (zie onder). Geen token nodig bij public repo.
#
# Installatie op Mini-PC (eenmalig):
#   GITHUB_REPO="jouwnaam/cyberwolfert" BACKEND_DIR=/home/wolfert/cyberwolfert/backend \
#     sudo -E bash scripts/minipc-release-sync.sh install
#
# Handmatig draaien:
#   GITHUB_REPO="jouwnaam/cyberwolfert" bash scripts/minipc-release-sync.sh
set -u
REPO="${GITHUB_REPO:-}"
BACKEND_DIR="${BACKEND_DIR:-/home/wolfert/cyberwolfert/backend}"
STATE="$BACKEND_DIR/.release-seen"

if [ "${1:-}" = "install" ]; then
  cat > /etc/systemd/system/cyberwolfert-release-sync.service <<EOF
[Unit]
Description=CyberWolfert release-sync (GitHub -> Mini-PC)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
User=wolfert
Environment=GITHUB_REPO=$REPO
Environment=BACKEND_DIR=$BACKEND_DIR
ExecStart=/bin/bash $BACKEND_DIR/../scripts-repo/minipc-release-sync.sh
EOF
  cat > /etc/systemd/system/cyberwolfert-release-sync.timer <<EOF
[Unit]
Description=Elke 15 min releases ophalen
[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now cyberwolfert-release-sync.timer
  echo "Timer actief."
  exit 0
fi

[ -z "$REPO" ] && { echo "GITHUB_REPO ontbreekt"; exit 1; }
mkdir -p "$BACKEND_DIR/public" "$BACKEND_DIR/downloads"

API="https://api.github.com/repos/$REPO/releases/latest"
JSON="$(curl -s -m 20 "$API")" || exit 0
TAG="$(echo "$JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
[ -z "$TAG" ] && exit 0
[ -f "$STATE" ] && [ "$(cat "$STATE")" = "$TAG" ] && exit 0
echo "Nieuwe release: $TAG"

dl() { # $1 = asset-naam, $2 = doelbestand
  URL="$(echo "$JSON" | grep -o '"browser_download_url": *"[^"]*/'"$1"'"' | head -1 | cut -d'"' -f4)"
  [ -z "$URL" ] && { echo "asset $1 ontbreekt"; return 1; }
  curl -sL -m 300 -o "$2.tmp" "$URL" && mv "$2.tmp" "$2"
}

cd /tmp || exit 1
dl "CyberWolfert-web.zip" web.zip && rm -rf "$BACKEND_DIR/public" && mkdir -p "$BACKEND_DIR/public" && unzip -qo web.zip -d "$BACKEND_DIR/public-tmp" && rm -rf "$BACKEND_DIR/public" && mv "$BACKEND_DIR/public-tmp/web" "$BACKEND_DIR/public" && rm -f web.zip && echo "web bijgewerkt"
dl "CyberWolfert.apk" "$BACKEND_DIR/downloads/CyberWolfert.apk" && echo "apk bijgewerkt"
dl "CyberWolfert-Windows.zip" "$BACKEND_DIR/downloads/CyberWolfert-Windows.zip" && echo "windows bijgewerkt"
dl "CyberWolfert-apps.zip" "$BACKEND_DIR/downloads/CyberWolfert-apps.zip" && echo "bundle bijgewerkt"

# version.json synchroniseren met release-tag (v1.8.0 -> version/build)
VER="$(echo "$TAG" | sed 's/^v//')"
if [ -n "$VER" ]; then
  python3 - "$BACKEND_DIR/version.json" "$VER" <<'EOF'
import json, sys
p, ver = sys.argv[1], sys.argv[2]
try:
    j = json.load(open(p))
except Exception:
    j = {}
j['version'] = ver
j['build'] = int(j.get('build', 0)) + 1
j['notes'] = f"Release {ver} via GitHub"
from datetime import date
j['updatedAt'] = date.today().isoformat()
json.dump(j, open(p, 'w'), indent=2)
print("version.json:", ver, j['build'])
EOF
fi

echo "$TAG" > "$STATE"
# Discord-melding via backend-log-API
SECRET="$(grep -E '^LOG_SECRET=' "$BACKEND_DIR/config.env" 2>/dev/null | cut -d= -f2)"
if [ -n "$SECRET" ]; then
  curl -s -m 10 -X POST http://127.0.0.1:43711/api/logs \
    -H 'Content-Type: application/json' \
    -d "{\"secret\":\"$SECRET\",\"channel\":\"appsUpdates\",\"text\":\"📱 Release $TAG automatisch uitgerold op Mini-PC.\"}" > /dev/null
fi
echo "Klaar: $TAG live."
