#!/usr/bin/env bash
# Pile web et PHP pour GLPI 10 — issue #7.
# Usage :  sudo ./install-web-php.sh

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars GLPI_FQDN GLPI_CODE_DIR GLPI_VAR_DIR TLS_MODE

HERE="$(dirname "$(readlink -f "$0")")"

log "=== Installation Apache et PHP ==="
apt_refresh
apt_install apache2 \
  php php-cli php-fpm \
  php-mysql php-curl php-gd php-intl php-mbstring php-xml php-zip \
  php-bz2 php-ldap php-imap php-opcache php-bcmath \
  openssl ca-certificates

PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
log "PHP détecté : $PHP_VER"

# --- Modules Apache requis ---------------------------------------------------
a2enmod rewrite ssl headers >/dev/null
a2dismod -f autoindex status 2>/dev/null || true
ok "Modules Apache configurés"

# --- Réglages PHP ------------------------------------------------------------
for sapi in apache2 cli; do
  d="/etc/php/${PHP_VER}/${sapi}/conf.d"
  [ -d "$d" ] && install -D -m 0644 "$HERE/php-glpi.ini" "$d/99-glpi.ini"
done
ok "Réglages PHP déposés"

# --- Certificat TLS — issue #11 ----------------------------------------------
TLS_DIR=/etc/ssl/glpi
if [ "$TLS_MODE" = "letsencrypt" ]; then
  require_vars TLS_EMAIL
  apt_install certbot python3-certbot-apache
  log "Le certificat Let's Encrypt sera émis après la mise en place de l'hôte virtuel."
  TLS_CERT="/etc/letsencrypt/live/${GLPI_FQDN}/fullchain.pem"
  TLS_KEY="/etc/letsencrypt/live/${GLPI_FQDN}/privkey.pem"
  # Certificat temporaire, remplacé par certbot : Apache doit pouvoir démarrer.
  if [ ! -f "$TLS_CERT" ]; then
    mkdir -p "$TLS_DIR"
    openssl req -x509 -nodes -newkey rsa:4096 -days 30 \
      -keyout "$TLS_DIR/temp.key" -out "$TLS_DIR/temp.crt" \
      -subj "/CN=${GLPI_FQDN}" >/dev/null 2>&1
    TLS_CERT="$TLS_DIR/temp.crt"; TLS_KEY="$TLS_DIR/temp.key"
    warn "Certificat temporaire en place. Lancer ensuite :"
    warn "  certbot --apache -d ${GLPI_FQDN} --email ${TLS_EMAIL} --agree-tos -n"
  fi
else
  # Lab non joignable depuis Internet : autorité interne. Le choix doit être
  # justifié dans la documentation technique (issue #36).
  mkdir -p "$TLS_DIR"; chmod 700 "$TLS_DIR"
  if [ ! -f "$TLS_DIR/glpi.crt" ]; then
    log "Génération d'un certificat auto-signé (2 ans) pour $GLPI_FQDN"
    openssl req -x509 -nodes -newkey rsa:4096 -days 730 \
      -keyout "$TLS_DIR/glpi.key" -out "$TLS_DIR/glpi.crt" \
      -subj "/C=FR/O=Lab GLPI/CN=${GLPI_FQDN}" \
      -addext "subjectAltName=DNS:${GLPI_FQDN},IP:${VPN_SRV_IP:-127.0.0.1}" >/dev/null 2>&1
    chmod 600 "$TLS_DIR/glpi.key"
    ok "Certificat généré — à importer comme autorité de confiance sur le client"
  fi
  TLS_CERT="$TLS_DIR/glpi.crt"; TLS_KEY="$TLS_DIR/glpi.key"
fi

# --- Hôte virtuel ------------------------------------------------------------
sed -e "s|@GLPI_FQDN@|$GLPI_FQDN|g" \
    -e "s|@GLPI_CODE_DIR@|$GLPI_CODE_DIR|g" \
    -e "s|@GLPI_VAR_DIR@|$GLPI_VAR_DIR|g" \
    -e "s|@TLS_CERT@|$TLS_CERT|g" \
    -e "s|@TLS_KEY@|$TLS_KEY|g" \
    "$HERE/apache-glpi.conf" > /etc/apache2/sites-available/glpi.conf

a2dissite 000-default default-ssl >/dev/null 2>&1 || true
a2ensite glpi >/dev/null

# Ne pas divulguer la version d'Apache — CDC §3.4.
write_file /etc/apache2/conf-available/security-local.conf <<'CFG' || true
ServerTokens Prod
ServerSignature Off
TraceEnable Off
CFG
a2enconf security-local >/dev/null

apache2ctl configtest || die "Configuration Apache invalide."
systemctl reload apache2
ok "Hôte virtuel GLPI actif sur https://${GLPI_FQDN}"

echo
log "Vérifications (critères de l'issue #7) :"
curl -sI "http://localhost" 2>/dev/null | grep -iE '^(server|x-powered-by):' \
  && warn "Des en-têtes divulguent encore la technologie" \
  || ok "Aucun en-tête ne divulgue la technologie"
php -i | grep -E 'session.cookie_(httponly|secure|samesite)' | sed 's/^/    /'
