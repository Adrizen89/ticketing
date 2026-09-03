#!/usr/bin/env bash
# Révocation d'un accès VPN — critère « la révocation coupe l'accès
# immédiatement », issues #16 et #17.
# Usage :  sudo ./revoke-client.sh <nom-utilisateur>

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root

CN="${1:-}"
[ -n "$CN" ] || die "Usage : $0 <nom-utilisateur>"

EASYRSA_DIR=/etc/openvpn/server/easy-rsa
cd "$EASYRSA_DIR"

log "Révocation du certificat de « $CN »"
./easyrsa --batch revoke "$CN"
./easyrsa --batch gen-crl
cp -a pki/crl.pem /etc/openvpn/server/pki/crl.pem
chmod 644 /etc/openvpn/server/pki/crl.pem

# La liste de révocation n'est prise en compte que si le serveur la lit.
if ! grep -q '^crl-verify' /etc/openvpn/server/server.conf; then
  echo 'crl-verify /etc/openvpn/server/pki/crl.pem' >> /etc/openvpn/server/server.conf
  log "Directive crl-verify ajoutée à la configuration serveur"
fi

# Le second facteur est retiré : même avec un certificat non encore révoqué
# côté cache, l'authentification PAM échouera.
rm -rf "/etc/openvpn/otp/$CN"
usermod -L "$CN" 2>/dev/null || true

systemctl restart openvpn-server@server
ok "Accès de « $CN » révoqué (certificat, second facteur, compte)"

log "Sessions actives restantes :"
grep -c '^CLIENT_LIST' /var/log/openvpn/status.log 2>/dev/null | sed 's/^/    connexions : /' || true
