#!/usr/bin/env bash
# Installation de GLPI 10 — issue #9.
# Usage :  sudo ./install-glpi.sh
#
# Déploie GLPI avec l'arborescence séparée recommandée : le code, la
# configuration, les données et les journaux vivent dans quatre répertoires
# distincts. C'est ce qui permet à l'issue #10 de garantir que config/ et files/
# ne sont jamais servis par le serveur web.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars GLPI_VERSION GLPI_SHA256 GLPI_CODE_DIR GLPI_CONFIG_DIR GLPI_VAR_DIR GLPI_LOG_DIR \
             DB_HOST DB_NAME DB_USER DB_PASSWORD

TARBALL="glpi-${GLPI_VERSION}.tgz"
URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${TARBALL}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

log "=== Installation de GLPI ${GLPI_VERSION} ==="

if [ -d "$GLPI_CODE_DIR" ] && [ -f "$GLPI_CODE_DIR/inc/downstream.php" ]; then
  warn "GLPI semble déjà installé dans $GLPI_CODE_DIR."
  confirm "Réinstaller par-dessus (la base et $GLPI_CONFIG_DIR sont conservés) ?" || exit 0
fi

# --- Téléchargement et vérification d'intégrité ------------------------------
# CDC §3, risque « défaillances d'intégrité des données » : ne jamais décompresser
# une archive dont l'empreinte n'a pas été vérifiée.
log "Téléchargement depuis $URL"
curl -fsSL --proto '=https' --tlsv1.2 -o "$WORK/$TARBALL" "$URL" \
  || die "Téléchargement impossible. Vérifier GLPI_VERSION et l'accès réseau sortant."

log "Vérification de l'empreinte SHA-256"
ACTUAL=$(sha256sum "$WORK/$TARBALL" | awk '{print $1}')
if [ "$ACTUAL" != "$GLPI_SHA256" ]; then
  die "Empreinte non conforme.
       attendue : $GLPI_SHA256
       obtenue  : $ACTUAL
       L'archive est corrompue ou altérée : installation interrompue."
fi
ok "Empreinte vérifiée : $ACTUAL"

# --- Déploiement du code -----------------------------------------------------
tar -xzf "$WORK/$TARBALL" -C "$WORK"
mkdir -p "$(dirname "$GLPI_CODE_DIR")"
rm -rf "${GLPI_CODE_DIR}.previous"
[ -d "$GLPI_CODE_DIR" ] && mv "$GLPI_CODE_DIR" "${GLPI_CODE_DIR}.previous"
mv "$WORK/glpi" "$GLPI_CODE_DIR"
ok "Code déployé dans $GLPI_CODE_DIR"

# --- Arborescence séparée ----------------------------------------------------
mkdir -p "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"

# Le code cherche sa configuration ici plutôt que dans son propre répertoire.
cat > "$GLPI_CODE_DIR/inc/downstream.php" <<PHP
<?php
// Arborescence séparée — issue #9. Généré par install-glpi.sh, ne pas éditer.
define('GLPI_CONFIG_DIR', '${GLPI_CONFIG_DIR}');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
PHP

cat > "$GLPI_CONFIG_DIR/local_define.php" <<PHP
<?php
// Emplacement des données et des journaux — issue #9.
define('GLPI_VAR_DIR', '${GLPI_VAR_DIR}');
define('GLPI_LOG_DIR', '${GLPI_LOG_DIR}');
PHP

# Sous-répertoires attendus par GLPI sous GLPI_VAR_DIR.
for d in _cache _cron _dumps _graphs _lock _pictures _plugins _rss _sessions \
         _tmp _uploads _plugins _inventories _plugins _plugins/_files _documents; do
  mkdir -p "$GLPI_VAR_DIR/$d"
done
ok "Arborescence séparée en place (config, données, journaux)"

# --- Droits ------------------------------------------------------------------
# Le serveur web n'écrit que là où il doit écrire. Le code lui est en lecture
# seule : une exécution de code arbitraire ne peut pas se réécrire en persistance.
WWW_USER="${WWW_USER:-www-data}"
chown -R root:root "$GLPI_CODE_DIR"
find "$GLPI_CODE_DIR" -type d -exec chmod 755 {} +
find "$GLPI_CODE_DIR" -type f -exec chmod 644 {} +

chown -R "$WWW_USER:$WWW_USER" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"
chmod 750 "$GLPI_VAR_DIR" "$GLPI_LOG_DIR"

chown -R root:"$WWW_USER" "$GLPI_CONFIG_DIR"
chmod 750 "$GLPI_CONFIG_DIR"
ok "Droits appliqués : code en lecture seule pour $WWW_USER"

# --- Installation en ligne de commande ---------------------------------------
# L'assistant web est contourné : le mot de passe de base ne transite pas dans
# un formulaire et l'installation devient reproductible depuis ce script.
if [ -f "$GLPI_CONFIG_DIR/config_db.php" ]; then
  warn "config_db.php existe déjà : base conservée, assistant non relancé."
else
  log "Exécution de l'assistant d'installation en ligne de commande"
  sudo -u "$WWW_USER" php "$GLPI_CODE_DIR/bin/console" db:install \
      --db-host="$DB_HOST" \
      --db-name="$DB_NAME" \
      --db-user="$DB_USER" \
      --db-password="$DB_PASSWORD" \
      --default-language=fr_FR \
      --no-interaction --quiet \
    || die "Installation GLPI échouée. Vérifier les prérequis : bin/console glpi:system:check_requirements"
  ok "Schéma créé en base"
fi

echo
ok "=== GLPI ${GLPI_VERSION} installé ==="
warn "ÉTAPES OBLIGATOIRES IMMÉDIATES :"
warn "  1. Lancer ./secure-glpi.sh   (issue #10 — supprime install/, verrouille les droits)"
warn "  2. Changer les mots de passe des 4 comptes par défaut : glpi, tech, normal, post-only"
warn "     -> tant que ce n'est pas fait, l'instance est ouverte à quiconque atteint le tunnel."
