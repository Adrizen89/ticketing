#!/usr/bin/env bash
# Sauvegarde chiffrée de GLPI — issues #6 et #14.
# Usage :  sudo ./backup-glpi.sh
#
# Deux volumes à sauvegarder : la base de données et le répertoire files/ qui
# porte les documents attachés aux tickets. L'un sans l'autre ne restaure rien.
# Les archives sont chiffrées : elles contiennent les données des tickets.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars DB_NAME DB_USER DB_PASSWORD GLPI_VAR_DIR GLPI_CONFIG_DIR \
             BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_PASSPHRASE

STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/$STAMP"
mkdir -p "$DEST"; chmod 700 "$BACKUP_DIR" "$DEST"

fail() { warn "$1"; rm -rf "$DEST"; exit 1; }

log "=== Sauvegarde GLPI — $STAMP ==="

# --- 1. Base de données ------------------------------------------------------
# --single-transaction : sauvegarde cohérente sans verrouiller l'application.
log "Export de la base « $DB_NAME »"
MYSQL_PWD="$DB_PASSWORD" mariadb-dump \
    --user="$DB_USER" --host="${DB_HOST:-127.0.0.1}" \
    --single-transaction --quick --routines --triggers --events \
    --default-character-set=utf8mb4 \
    "$DB_NAME" 2>"$DEST/dump.err" \
  | gzip -9 > "$DEST/base.sql.gz" || fail "Export de la base échoué — voir $DEST/dump.err"

[ -s "$DEST/base.sql.gz" ] || fail "Export vide : sauvegarde inutilisable."
rm -f "$DEST/dump.err"
ok "Base exportée ($(du -h "$DEST/base.sql.gz" | cut -f1))"

# --- 2. Documents et configuration -------------------------------------------
log "Archivage des documents et de la configuration"
tar -czf "$DEST/fichiers.tar.gz" \
    -C "$(dirname "$GLPI_VAR_DIR")" "$(basename "$GLPI_VAR_DIR")" \
    -C "$(dirname "$GLPI_CONFIG_DIR")" "$(basename "$GLPI_CONFIG_DIR")" \
  || fail "Archivage échoué"
ok "Documents archivés ($(du -h "$DEST/fichiers.tar.gz" | cut -f1))"

# --- 3. Chiffrement ----------------------------------------------------------
# Une sauvegarde en clair déplace le problème : elle contient tout ce que la
# base protège. CDC §3.3, chiffrement des données sensibles au repos.
log "Chiffrement des archives"
for f in base.sql.gz fichiers.tar.gz; do
  openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
      -in "$DEST/$f" -out "$DEST/${f}.enc" \
      -pass env:BACKUP_PASSPHRASE || fail "Chiffrement de $f échoué"
  shred -u "$DEST/$f"
done
ok "Archives chiffrées en AES-256"

# --- 4. Empreintes et manifeste ----------------------------------------------
( cd "$DEST" && sha256sum ./*.enc > SHA256SUMS )
cat > "$DEST/manifeste.txt" <<MAN
Sauvegarde GLPI
Date          : $(date -Iseconds)
Machine       : $(hostname -f)
Version GLPI  : ${GLPI_VERSION:-inconnue}
Base          : ${DB_NAME}
Chiffrement   : AES-256-CBC, PBKDF2 200000 iterations
Restauration  : ./restore-glpi.sh ${STAMP}
MAN
chmod 600 "$DEST"/*
ok "Empreintes et manifeste écrits"

# --- 5. Purge ----------------------------------------------------------------
log "Purge des sauvegardes de plus de $BACKUP_RETENTION_DAYS jours"
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+$BACKUP_RETENTION_DAYS" \
     -exec rm -rf {} + 2>/dev/null || true

echo
ok "=== Sauvegarde terminée : $DEST ==="
du -sh "$DEST" | sed 's/^/    /'
warn "Critère de l'issue #6 : les sauvegardes ne doivent pas rester uniquement"
warn "sur la machine sauvegardée. Copier $DEST vers un stockage externe."
