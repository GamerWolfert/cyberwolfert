# 🐺 CyberWolfert — browser + WolfPulse + CyberWolf AI

Productie draait op de Mini-PC (`192.168.1.42`, systemd). Releases bouwen in de
cloud (GitHub Actions, tag `v*`); de Mini-PC haalt ze automatisch op
(`scripts/minipc-release-sync.sh`, elke 15 min). Website = meteen live,
Android updatet zichzelf in de app, Windows via 1-klik download.

```
app/        Flutter (Android/iOS/Windows/Web) — auto-update ingebouwd
backend/    Node + Express API (config via backend/config.env, zie .env.example)
scripts/    publish, tunnels, Mini-PC beheer, release-sync
tunnel/     ngrok/cloudflared voorbeelden
```

## Nieuwe release uitbrengen

```bash
# versie bumpen: backend/version.json + app/pubspec.yaml + UpdateService.currentBuild
git tag v1.8.0 && git push origin v1.8.0
# -> Actions bouwt APK + Windows-zip + web-zip + bundle -> GitHub Release
# -> Mini-PC pult binnen 15 min alles binnen (public + downloads + version.json)
```

## Lokaal bouwen (zonder cloud)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish_update.ps1 -Version "1.8.0" -Notes "..." -ApiBaseUrl "http://192.168.1.42:43711/api"
```
