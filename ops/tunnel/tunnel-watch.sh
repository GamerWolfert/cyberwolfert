#!/bin/bash
# Vangt de actuele quick-tunnel-URL op (uit journal) en publiceert die via de backend.
PUB=/home/wolfert/cyberwolfert/backend/public/tunnel.txt
JSON=/home/wolfert/cyberwolfert/backend/tunnel.json

mkdir -p "$(dirname "$PUB")" "$(dirname "$JSON")"

scan() {
  printf '%s' "$1" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1
}

publish() {
  local u="$1"
  [ -z "$u" ] && return
  if [ "$u" != "$(cat "$PUB" 2>/dev/null)" ]; then
    printf '%s\n' "$u" > "$PUB"
    printf '{"url":"%s","updatedAt":"%s"}\n' "$u" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$JSON"
    echo "[tunnel-watch] nieuwe URL: $u"
  fi
}

# 1) alles wat al gelogd is
publish "$(scan "$(journalctl -u cloudflared-quick.service --since '-30 min' --output=cat 2>/dev/null)")"

# 2) live blijven meelezen
journalctl -u cloudflared-quick.service -f -n 0 --output=cat 2>/dev/null | while IFS= read -r line; do
  u=$(scan "$line")
  publish "$u"
done
