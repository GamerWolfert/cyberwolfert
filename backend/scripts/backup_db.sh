#!/bin/bash
# Nachtelijke PostgreSQL-backup met rotatie (14 dagen).
# De database is al eens gecrasht op een volle schijf; een recente dump is dan
# het enige wat je redt. Draait als root via cyberwolfert-dbbackup.timer.
set -u
DEST=/var/backups/cyberwolfert
KEEP=14
mkdir -p "$DEST"
STAMP=$(date +%F)
OUT="$DEST/db-$STAMP.dump"

export PGPASSWORD=Leeuwen2011
if ! pg_dump -h 127.0.0.1 -U wolfert -d cyberwolfert_db -Fc -f "$OUT"; then
  echo "[dbbackup] pg_dump MISLUKT op $STAMP" >&2
  rm -f "$OUT"
  exit 1
fi
chmod 600 "$OUT"
# altijd de nieuwste dump onder een vaste naam
ln -sf "$OUT" "$DEST/latest.dump"

# rotatie: houd de $KEEP nieuwste dumps
ls -1t "$DEST"/db-*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do
  rm -f "$f"
done

SIZE=$(du -h "$OUT" | cut -f1)
echo "[dbbackup] $STAMP ok ($SIZE), $(ls -1 "$DEST"/db-*.dump | wc -l) dumps bewaard"
