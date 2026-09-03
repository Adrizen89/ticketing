#!/usr/bin/env bash
# Scénario 4 — le certificat seul ne suffit pas à monter le tunnel — issue #33.
# Usage :  ./scenario4-mfa.sh
#
# Éprouve le second facteur du VPN (issue #17). Un profil client valide, mais
# sans code TOTP correct, doit être refusé. À jouer depuis le poste client.
#
# Ce test ne peut pas être entièrement automatisé sans exposer un secret TOTP :
# il guide l'opérateur et recueille le résultat, plutôt que de simuler le code.

set -uo pipefail
OUT="$(dirname "$0")/preuves"; mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S); REPORT="$OUT/scenario4-$STAMP.txt"
PROFIL="${1:-/etc/openvpn/client/lab.conf}"

{
  echo "=============================================================="
  echo " Scénario 4 — contournement du second facteur VPN — issue #33"
  echo " Profil : $PROFIL"
  echo " Date   : $(date -Iseconds)"
  echo "=============================================================="
  echo
  echo "### Protocole"
  echo "1. Le profil client possède un certificat valide (premier facteur)."
  echo "2. Tenter de monter le tunnel en fournissant un identifiant correct"
  echo "   mais un code à usage unique FAUX ou VIDE."
  echo "3. Le tunnel doit être REFUSÉ à l'authentification."
  echo "4. Répéter avec le bon code : le tunnel doit alors monter."
  echo
  echo "### 3a. Tentative avec un mauvais code (attendu : AUTH_FAILED)"
  echo "  Commande jouée :"
  echo "    printf 'utilisateur\\n000000\\n' | sudo openvpn --config $PROFIL --auth-nocache"
  echo
  if [ -f "$PROFIL" ]; then
    printf 'test\n000000\n' | timeout 25 openvpn --config "$PROFIL" \
        --auth-user-pass /dev/stdin --connect-retry-max 1 --verb 3 2>&1 \
      | grep -iE 'AUTH_FAILED|auth-failure|TLS Error|Options error|Initialization Sequence' \
      | sed 's/^/  /' | head -8 || echo "  (analyser la sortie complète d'OpenVPN)"
  else
    echo "  Profil absent : jouer la commande ci-dessus manuellement."
  fi
  echo
  echo "### Résultat côté serveur"
  echo "  Relever sur le serveur :"
  echo "    sudo grep -iE 'AUTH_FAILED|authentication' /var/log/openvpn/openvpn.log | tail"
  echo "  et l'éventuel bannissement Fail2ban :"
  echo "    sudo fail2ban-client status openvpn"
  echo
  echo "### Interprétation"
  echo "Conforme si : la connexion avec un mauvais code est refusée (AUTH_FAILED)"
  echo "et si le même profil, avec le bon code, monte le tunnel. Cela prouve que"
  echo "le certificat seul ne donne pas l'accès — le second facteur est effectif."
} 2>&1 | tee "$REPORT"

echo; echo "Rapport : $REPORT"
