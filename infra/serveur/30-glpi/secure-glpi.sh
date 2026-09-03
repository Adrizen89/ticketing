#!/usr/bin/env bash
# Sécurisation de GLPI après l'assistant — issue #10.
# Usage :  sudo ./secure-glpi.sh
#
# CDC §3 « mauvaise configuration de sécurité ». À exécuter systématiquement
# après toute installation ou montée de version.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars GLPI_CODE_DIR GLPI_CONFIG_DIR GLPI_VAR_DIR GLPI_FQDN

WWW_USER="${WWW_USER:-www-data}"
FAIL=0

log "=== Sécurisation post-installation de GLPI ==="

# --- 1. Neutraliser le répertoire d'installation -----------------------------
# install.php laissé en place permet de relancer l'assistant et de réinitialiser
# la configuration de connexion à la base.
if [ -d "$GLPI_CODE_DIR/install" ]; then
  mv "$GLPI_CODE_DIR/install" "/root/glpi-install-$(date +%Y%m%d%H%M%S).bak"
  ok "Répertoire install/ retiré du code et archivé dans /root"
else
  ok "Répertoire install/ déjà absent"
fi

# --- 2. Retirer les fichiers résiduels ---------------------------------------
for f in CHANGELOG.md CONTRIBUTING.md SECURITY.md UPGRADE.md; do
  [ -f "$GLPI_CODE_DIR/$f" ] && rm -f "$GLPI_CODE_DIR/$f"
done
ok "Fichiers résiduels retirés"

# --- 3. Reverrouiller les droits ---------------------------------------------
chown -R root:root "$GLPI_CODE_DIR"
find "$GLPI_CODE_DIR" -type d -exec chmod 755 {} +
find "$GLPI_CODE_DIR" -type f -exec chmod 644 {} +
chown -R "$WWW_USER:$WWW_USER" "$GLPI_VAR_DIR"
chmod -R o-rwx "$GLPI_VAR_DIR"
chown -R root:"$WWW_USER" "$GLPI_CONFIG_DIR"
chmod 750 "$GLPI_CONFIG_DIR"
find "$GLPI_CONFIG_DIR" -type f -exec chmod 640 {} +
ok "Droits reverrouillés"

# --- 4. Interdire l'exécution de PHP dans les fichiers déposés ---------------
# Défense en profondeur : même si un fichier PHP passait les contrôles de type
# de GLPI, il ne serait pas interprété.
write_file "$GLPI_VAR_DIR/.htaccess" 0644 "root:$WWW_USER" <<'HT' || true
# Aucune exécution ici — issue #10.
php_flag engine off
<FilesMatch "\.(php|phtml|php[0-9]|phar|cgi|pl|py|sh)$">
    Require all denied
</FilesMatch>
Options -Indexes -ExecCGI
HT

# --- 5. Vérifications --------------------------------------------------------
echo
log "Vérifications des critères d'acceptation de l'issue #10 :"

check() {
  local label="$1" url="$2" expect="$3"
  local code
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expect" ] || { [ "$expect" = "40x" ] && [[ "$code" =~ ^4 ]]; }; then
    ok "  $label -> HTTP $code"
  else
    warn "  $label -> HTTP $code (attendu $expect)"
    FAIL=1
  fi
}

BASE="https://${GLPI_FQDN}"
check "install/install.php inaccessible" "$BASE/install/install.php" "40x"
check "config/config_db.php inaccessible" "$BASE/config/config_db.php" "40x"
check "files/ inaccessible"               "$BASE/files/" "40x"
check "page de connexion servie"          "$BASE/index.php" "200"

# Preuve du critère « un fichier PHP déposé n'est pas exécuté ».
PROBE="$GLPI_VAR_DIR/_uploads/probe-$$.php"
mkdir -p "$(dirname "$PROBE")"
echo '<?php echo "EXECUTE"; ?>' > "$PROBE"
BODY=$(curl -sk --max-time 5 "$BASE/files/_uploads/$(basename "$PROBE")" 2>/dev/null || true)
if echo "$BODY" | grep -q "EXECUTE"; then
  warn "  ÉCHEC : un fichier PHP déposé est exécuté par le serveur web"
  FAIL=1
else
  ok "  Fichier PHP déposé non exécuté"
fi
rm -f "$PROBE"

echo
if [ "$FAIL" -eq 0 ]; then
  ok "=== Tous les contrôles passent ==="
else
  warn "=== Des contrôles ont échoué — corriger avant de poursuivre ==="
fi

warn "Contrôle manuel restant : les 4 comptes par défaut (glpi, tech, normal,"
warn "post-only) doivent avoir un mot de passe changé ou être désactivés."
warn "GLPI signale lui-même les comptes concernés dans Configuration > Notifications."
exit "$FAIL"
