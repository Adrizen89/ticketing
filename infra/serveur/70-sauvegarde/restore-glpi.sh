#!/usr/bin/env bash
# Restauration de GLPI — issues #6 et #14.
# Usage :  sudo ./restore-glpi.sh <horodatage>       (ex. 20260903-021500)
#          sudo ./restore-glpi.sh --list
#
# Le critère d'acceptation est explicite : « une restauration a été réalisée au
# moins une fois et son déroulé est consigné ». Ce script est fait pour être
# exécuté pour de vrai, pas pour rester en réserve.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars DB_NAME DB_USER DB_PASSWORD GLPI_VAR_DIR GLPI_CONFIG_DIR \
             BACKUP_DIR BACKUP_PASSPHRASE

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  log "Sauvegardes disponibles dans $BACKUP_DIR :"
  ls -1 "$BACKUP_DIR" 2>/dev/null | sed 's/^/    /' || warn "aucune"
  exit 0
fi

STAMP="$1"
SRC="$BACKUP_DIR/$STAMP"
[ -d "$SRC" ] || die "Sauvegarde introuvable : $SRC"

log "=== Restauration depuis $STAMP ==="
cat "$SRC/manifeste.txt" 2>/dev/null | sed 's/^/    /'
echo
warn "Cette opération ÉCRASE la base « $DB_NAME » et le contenu de $GLPI_VAR_DIR."
confirm "Confirmer la restauration ?" || die "Restauration annulée."

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# --- 1. Vérification d'intégrité avant toute écriture ------------------------
log "Vérification des empreintes"
( cd "$SRC" && sha256sum -c SHA256SUMS --quiet ) \
  || die "Empreintes non conformes : archive corrompue, restauration interrompue."
ok "Intégrité vérifiée"

# --- 2. Déchiffrement --------------------------------------------------------
log "Déchiffrement"
for f in base.sql.gz fichiers.tar.gz; do
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
      -in "$SRC/${f}.enc" -out "$WORK/$f" \
      -pass env:BACKUP_PASSPHRASE \
    || die "Déchiffrement de $f échoué — passphrase incorrecte ?"
done
ok "Archives déchiffrées"

# --- 3. Filet de sécurité : sauvegarder l'état courant avant d'écraser -------
log "Sauvegarde de sécurité de l'état courant"
SAFETY="$BACKUP_DIR/avant-restauration-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"
MYSQL_PWD="$DB_PASSWORD" mariadb-dump --user="$DB_USER" --single-transaction \
    "$DB_NAME" 2>/dev/null | gzip > "$SAFETY/base.sql.gz" || true
ok "État courant sauvegardé dans $SAFETY"

systemctl stop apache2 2>/dev/null || true

# --- 4. Restauration de la base ----------------------------------------------
log "Restauration de la base"
MYSQL_PWD="$DB_PASSWORD" mariadb --user="$DB_USER" \
    -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;
        CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
gunzip -c "$WORK/base.sql.gz" | MYSQL_PWD="$DB_PASSWORD" mariadb --user="$DB_USER" "$DB_NAME" \
  || die "Import de la base échoué. État précédent disponible dans $SAFETY"
ok "Base restaurée"

# --- 5. Restauration des documents -------------------------------------------
log "Restauration des documents et de la configuration"
tar -xzf "$WORK/fichiers.tar.gz" -C "$(dirname "$GLPI_VAR_DIR")" \
  || die "Extraction échouée"
chown -R www-data:www-data "$GLPI_VAR_DIR"
chown -R root:www-data "$GLPI_CONFIG_DIR"
chmod 750 "$GLPI_CONFIG_DIR"
ok "Documents restaurés"

systemctl start apache2

echo
ok "=== Restauration terminée ==="
log "Contrôles à effectuer maintenant :"
log "  1. GLPI répond    : curl -sk -o /dev/null -w '%{http_code}\\n' https://${GLPI_FQDN}/index.php"
log "  2. Connexion possible avec un compte connu"
log "  3. Un ticket avec pièce jointe s'ouvre et le document se télécharge"
log "  4. Consigner le déroulé et la durée — critère de l'issue #6"
