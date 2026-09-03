#!/usr/bin/env bash
# Serveur OpenVPN avec second facteur TOTP — issues #15 et #17.
# Usage :  sudo ./install-openvpn.sh

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars VPN_PORT VPN_PROTO VPN_SUBNET VPN_MASK GLPI_FQDN SRV_LAN_IP

HERE="$(dirname "$(readlink -f "$0")")"
PKI=/etc/openvpn/server/pki

log "=== Installation du serveur OpenVPN ==="
apt_refresh
apt_install openvpn easy-rsa openvpn-auth-ldap libpam-google-authenticator qrencode

mkdir -p /var/log/openvpn /etc/openvpn/otp
chmod 750 /etc/openvpn/otp

# --- Autorité de certification interne ---------------------------------------
# Les clés privées sont générées ici et n'en sortent jamais. Le répertoire pki/
# est exclu du dépôt par .gitignore.
if [ ! -f "$PKI/ca.crt" ]; then
  log "Création de l'autorité de certification interne"
  rm -rf /etc/openvpn/server/easy-rsa
  make-cadir /etc/openvpn/server/easy-rsa
  cd /etc/openvpn/server/easy-rsa

  cat > vars <<'VARS'
set_var EASYRSA_ALGO           ec
set_var EASYRSA_CURVE          secp384r1
set_var EASYRSA_DIGEST         "sha512"
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    825
set_var EASYRSA_CRL_DAYS       180
set_var EASYRSA_REQ_CN         "Lab GLPI VPN CA"
VARS

  ./easyrsa --batch init-pki
  ./easyrsa --batch --req-cn="Lab GLPI VPN CA" build-ca nopass
  ./easyrsa --batch build-server-full server nopass
  ./easyrsa --batch gen-crl

  mkdir -p "$PKI"
  cp -a pki/ca.crt pki/crl.pem "$PKI/"
  mkdir -p "$PKI/issued" "$PKI/private"
  cp -a pki/issued/server.crt "$PKI/issued/"
  cp -a pki/private/server.key "$PKI/private/"

  # tls-crypt chiffre le canal de contrôle : un observateur ne peut ni
  # identifier le protocole ni lancer d'attaque avant l'authentification.
  openvpn --genkey secret "$PKI/tls-crypt.key"

  chmod 700 "$PKI/private"; chmod 600 "$PKI/private/"* "$PKI/tls-crypt.key"
  ok "Autorité de certification et certificat serveur créés"
else
  ok "Autorité de certification déjà en place — conservée"
fi

# --- Configuration -----------------------------------------------------------
sed -e "s|@VPN_PORT@|$VPN_PORT|g" \
    -e "s|@VPN_PROTO@|$VPN_PROTO|g" \
    -e "s|@VPN_SUBNET@|$VPN_SUBNET|g" \
    -e "s|@VPN_MASK@|$VPN_MASK|g" \
    "$HERE/server.conf" > /etc/openvpn/server/server.conf
chmod 640 /etc/openvpn/server/server.conf

install -D -m 0644 "$HERE/pam-openvpn" /etc/pam.d/openvpn
ok "Configuration serveur et pile PAM déposées"

# --- Démarrage ---------------------------------------------------------------
systemctl enable --now openvpn-server@server
sleep 2
systemctl is-active --quiet openvpn-server@server \
  || die "OpenVPN n'a pas démarré. Journal : journalctl -u openvpn-server@server -n 50"
ok "Service OpenVPN actif"

echo
log "Vérifications (critères de l'issue #15) :"
ip -brief addr show tun0 2>/dev/null | sed 's/^/    /' || warn "tun0 pas encore monté"
log "Algorithme du canal de données :"
grep -E '^data-ciphers ' /etc/openvpn/server/server.conf | sed 's/^/    /'

echo
warn "SUITE : enrôler un utilisateur avec ./enroll-client.sh <nom-utilisateur>"
warn "Puis relancer 00-durcissement/harden.sh pour restreindre SSH à tun0 (issue #19)."
