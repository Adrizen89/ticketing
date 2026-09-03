#!/usr/bin/env bash
# Base de données GLPI en accès restreint — issue #8.
# Usage :  sudo ./install-mariadb.sh
#
# Idempotent : rejouable. Ne réinitialise jamais une base existante.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars DB_NAME DB_USER DB_PASSWORD

HERE="$(dirname "$(readlink -f "$0")")"

log "=== Installation et sécurisation de MariaDB ==="
apt_refresh
apt_install mariadb-server mariadb-client

install -D -m 0644 "$HERE/mariadb-glpi.cnf" /etc/mysql/mariadb.conf.d/99-glpi.cnf
mkdir -p /var/lib/mysql-files && chown mysql:mysql /var/lib/mysql-files
systemctl restart mariadb
ok "Configuration appliquée, service redémarré"

# --- Sécurisation initiale, équivalent de mysql_secure_installation ----------
log "Sécurisation initiale"
mariadb <<'SQL'
-- Suppression des comptes anonymes : ils permettent une connexion sans identité.
DELETE FROM mysql.global_priv WHERE User='';
-- Aucun accès root hors de la machine.
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
-- Suppression de la base de test, accessible à tous par défaut.
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
ok "Comptes anonymes et base de test supprimés, root distant interdit"

# --- Base et compte applicatif dédiés ----------------------------------------
# Droits limités au strict nécessaire : pas de GRANT ALL, pas de SUPER,
# pas de FILE. CDC §3.2 « moindre privilège ».
log "Création de la base « $DB_NAME » et du compte « $DB_USER »"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
  IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';

REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${DB_USER}'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER,
      CREATE TEMPORARY TABLES, LOCK TABLES, REFERENCES
  ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
ok "Base et compte applicatif créés"

# GLPI 10 a besoin d'un accès en lecture à mysql.time_zone_name pour gérer
# les fuseaux horaires. Droit accordé explicitement, et lui seul.
mariadb-tzinfo-to-sql /usr/share/zoneinfo 2>/dev/null | mariadb mysql || \
  warn "Import des fuseaux horaires incomplet — à vérifier si GLPI le signale"
mariadb -e "GRANT SELECT ON mysql.time_zone_name TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
ok "Fuseaux horaires disponibles pour GLPI"

echo
log "Vérifications (critères de l'issue #8) :"
if ss -tlnp | grep -q '0.0.0.0:3306\|:::3306'; then
  die "MariaDB écoute sur une interface réseau — le cloisonnement a échoué."
fi
ok "MariaDB n'écoute que sur la boucle locale :"
ss -tlnp | grep 3306 | sed 's/^/    /' || echo "    (aucune écoute externe)"

log "Droits effectifs du compte applicatif :"
mariadb -e "SHOW GRANTS FOR '${DB_USER}'@'localhost';" | sed 's/^/    /'

warn "Depuis le poste client, vérifier que la connexion échoue :"
warn "  mariadb -h ${SRV_LAN_IP:-<ip-serveur>} -u ${DB_USER} -p   ->  doit échouer"
