#!/usr/bin/env bash
# Enrôlement d'un accès VPN : certificat + second facteur TOTP — issues #16, #17.
# Usage :  sudo ./enroll-client.sh <nom-utilisateur>
#
# Produit un profil .ovpn unitaire. Un profil par poste, jamais de profil
# partagé : c'est ce qui rend la révocation individuelle possible.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars SRV_LAN_IP VPN_PORT VPN_PROTO

CN="${1:-}"
[ -n "$CN" ] || die "Usage : $0 <nom-utilisateur>"
[[ "$CN" =~ ^[a-z][a-z0-9_-]{2,31}$ ]] || die "Nom invalide : minuscules, chiffres, tiret, souligné."

EASYRSA_DIR=/etc/openvpn/server/easy-rsa
PKI="$EASYRSA_DIR/pki"
OUT="/root/vpn-profils"
mkdir -p "$OUT"; chmod 700 "$OUT"

# --- 1. Compte système dédié, sans shell -------------------------------------
# Le compte ne sert qu'à porter l'identité PAM du second facteur : il ne doit
# donner aucun accès au système. CDC §3.2, moindre privilège.
if ! id "$CN" >/dev/null 2>&1; then
  useradd --system --shell /usr/sbin/nologin --no-create-home "$CN"
  passwd -l "$CN" >/dev/null
  ok "Compte système « $CN » créé (sans shell, verrouillé)"
fi

# --- 2. Certificat client ----------------------------------------------------
cd "$EASYRSA_DIR"
if [ ! -f "$PKI/issued/${CN}.crt" ]; then
  ./easyrsa --batch build-client-full "$CN" nopass
  ok "Certificat client émis pour « $CN »"
else
  warn "Certificat déjà existant pour « $CN » — réutilisé"
fi

# --- 3. Second facteur TOTP --------------------------------------------------
OTP_DIR="/etc/openvpn/otp/$CN"
if [ ! -f "$OTP_DIR/.google_authenticator" ]; then
  mkdir -p "$OTP_DIR"
  # -t TOTP, -d pas de réutilisation de code, -f écriture directe,
  # -r 3 -R 30 limitation de débit, -w 3 tolérance de dérive d'horloge.
  google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 10 -q \
      -s "$OTP_DIR/.google_authenticator" -i "GLPI Lab" -n "$CN"
  chown -R root:root "$OTP_DIR"; chmod 700 "$OTP_DIR"
  chmod 600 "$OTP_DIR/.google_authenticator"
  ok "Second facteur TOTP généré"

  SECRET=$(head -n1 "$OTP_DIR/.google_authenticator")
  echo
  log "Enrôlement du second facteur pour « $CN » — à scanner MAINTENANT :"
  qrencode -t ANSIUTF8 "otpauth://totp/GLPI%20Lab:${CN}?secret=${SECRET}&issuer=GLPI%20Lab"
  echo
  warn "Codes de récupération à usage unique (à remettre par un canal sûr) :"
  tail -n +2 "$OTP_DIR/.google_authenticator" | grep -E '^[0-9]{8}$' | sed 's/^/    /'
  echo
  warn "Ce code QR et ces codes ne seront plus jamais réaffichés."
  confirm "Enrôlement effectué et codes conservés ?" || die "Enrôlement interrompu."
else
  warn "Second facteur déjà enrôlé pour « $CN » — conservé"
fi

# --- 4. Profil client unitaire -----------------------------------------------
PROFILE="$OUT/${CN}.ovpn"
cat > "$PROFILE" <<PROF
# Profil VPN — $CN — généré le $(date -Iseconds)
# Confidentiel : contient la clé privée du poste. Ne jamais versionner,
# ne jamais transmettre par un canal non chiffré.
client
dev tun
proto ${VPN_PROTO}
remote ${SRV_LAN_IP} ${VPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
data-ciphers AES-256-GCM
data-ciphers-fallback AES-256-GCM
auth SHA512
tls-version-min 1.2
verb 3

# Second facteur : identifiant + code à six chiffres demandés à chaque connexion.
auth-user-pass
auth-nocache

<ca>
$(cat "$PKI/ca.crt")
</ca>
<cert>
$(openssl x509 -in "$PKI/issued/${CN}.crt")
</cert>
<key>
$(cat "$PKI/private/${CN}.key")
</key>
<tls-crypt>
$(cat /etc/openvpn/server/pki/tls-crypt.key)
</tls-crypt>
PROF
chmod 600 "$PROFILE"

echo
ok "Profil généré : $PROFILE"
warn "Transfert vers le poste client par un canal sûr, par exemple :"
warn "  scp $PROFILE utilisateur@${CLI_LAN_IP:-<ip-client>}:~/"
warn "Puis SUPPRIMER le profil du serveur : shred -u $PROFILE"
warn "Le profil ne doit jamais être committé (.gitignore couvre *.ovpn)."
