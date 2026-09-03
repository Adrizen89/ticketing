#!/usr/bin/env bash
# Scénario 2 — force brute sur SSH et sur la connexion GLPI — issue #33.
# Usage :  sudo ./scenario2-force-brute.sh <ip-serveur> <fqdn-glpi>
#
# Éprouve la protection anti-force brute (issue #31) sur deux surfaces.
# À exécuter depuis un poste du tunnel, sur le lab uniquement, avec un compte
# de démonstration : c'est un test de sa propre infrastructure, pas une attaque.
#
# Preuve attendue : les premières tentatives passent (échec d'authentification
# normal), puis l'adresse est bannie et les tentatives suivantes n'obtiennent
# plus de réponse. Le déroulé horodaté est versable au rapport (issue #38).

set -uo pipefail
SRV="${1:-}"; FQDN="${2:-}"
[ -n "$SRV" ] && [ -n "$FQDN" ] || { echo "Usage : $0 <ip-serveur> <fqdn-glpi>" >&2; exit 1; }

OUT="$(dirname "$0")/preuves"; mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S); REPORT="$OUT/scenario2-$STAMP.txt"
SSH_PORT="${SSH_PORT:-22}"

{
  echo "=============================================================="
  echo " Scénario 2 — force brute — issue #33"
  echo " Cibles : ssh://$SRV:$SSH_PORT  et  https://$FQDN/front/login.php"
  echo " Date   : $(date -Iseconds)"
  echo " Cadre  : test du lab, compte de démonstration, dans le tunnel"
  echo "=============================================================="
  echo
  echo "### 1. Fail2ban AVANT le test"
  ssh -p "$SSH_PORT" -o BatchMode=yes "root@$SRV" \
      "fail2ban-client status sshd; echo; fail2ban-client status glpi-login" 2>&1 || \
      echo "(état à relever manuellement : fail2ban-client status)"
  echo

  echo "### 2. Bourrage SSH — 10 tentatives avec un mauvais mot de passe"
  for i in $(seq 1 10); do
    sshpass -p "mauvais-mot-de-passe-$i" \
      ssh -p "$SSH_PORT" -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no -o StrictHostKeyChecking=no \
          -o ConnectTimeout=3 "invalide@$SRV" true 2>&1 \
      | sed "s/^/  tentative $i : /" || true
  done
  echo

  echo "### 3. Bourrage GLPI — 12 connexions avec de mauvais identifiants"
  for i in $(seq 1 12); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 \
      -d "login_name=invalide&login_password=faux$i&_glpi_csrf_token=x" \
      "https://$FQDN/front/login.php" 2>/dev/null || echo "000")
    echo "  tentative $i : HTTP $code"
    sleep 1
  done
  echo

  echo "### 4. Fail2ban APRÈS le test — l'adresse doit être bannie"
  ssh -p "$SSH_PORT" -o BatchMode=yes "root@$SRV" \
      "fail2ban-client status sshd; echo; fail2ban-client status glpi-login" 2>&1 || \
      echo "(état à relever manuellement)"
  echo

  echo "### Interprétation"
  echo "Conforme si : l.adresse de test apparaît dans « Banned IP list » d'au moins"
  echo "une prison, et si une nouvelle tentative reste sans réponse jusqu'à"
  echo "expiration du bannissement. Sinon, revoir infra/serveur/60-supervision/"
  echo "fail2ban/ et vérifier les chemins de journaux."
} 2>&1 | tee "$REPORT"

echo; echo "Rapport : $REPORT"
command -v sshpass >/dev/null || echo "Note : installer sshpass pour la partie SSH (apt-get install sshpass)."
