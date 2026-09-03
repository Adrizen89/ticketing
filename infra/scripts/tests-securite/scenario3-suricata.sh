#!/usr/bin/env bash
# Scénario 3 — intrusion applicative détectée et bloquée par Suricata — issue #33.
# Usage :  ./scenario3-suricata.sh <fqdn-glpi>
#
# Envoie, depuis le tunnel, des requêtes que les règles locales de l'issue #27
# doivent bloquer, puis vérifie que l'alerte correspondante apparaît dans le
# journal de Suricata. Requêtes inoffensives : elles ne visent aucune faille
# réelle, elles déclenchent des signatures.

set -uo pipefail
FQDN="${1:-}"
[ -n "$FQDN" ] || { echo "Usage : $0 <fqdn-glpi>" >&2; exit 1; }

OUT="$(dirname "$0")/preuves"; mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S); REPORT="$OUT/scenario3-$STAMP.txt"
EVE="${EVE_JSON:-/var/log/suricata/eve.json}"

essais=(
  "acces install.php|https://$FQDN/install/install.php"
  "traversee de repertoire|https://$FQDN/../../../../etc/passwd"
  "injection SQL|https://$FQDN/front/computer.php?id=1%20UNION%20SELECT%20user,password%20FROM%20glpi_users"
  "scanner connu (User-Agent)|https://$FQDN/"
)

{
  echo "=============================================================="
  echo " Scénario 3 — détection et blocage Suricata — issue #33"
  echo " Cible : https://$FQDN   (depuis le tunnel)"
  echo " Date  : $(date -Iseconds)"
  echo "=============================================================="
  echo
  ligne_depart=$(wc -l < "$EVE" 2>/dev/null || echo 0)

  for e in "${essais[@]}"; do
    libelle="${e%%|*}"; url="${e#*|}"
    echo "### Requête : $libelle"
    if [[ "$libelle" == scanner* ]]; then
      code=$(curl -sk -A "sqlmap/1.7" -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
    else
      code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
    fi
    echo "  réponse : HTTP $code  (000 ou coupure = requête bloquée, résultat attendu)"
    echo
    sleep 1
  done

  echo "### Alertes Suricata déclenchées par ce test"
  if [ -r "$EVE" ] && command -v jq >/dev/null; then
    tail -n "+$((ligne_depart + 1))" "$EVE" \
      | jq -r 'select(.event_type=="alert")
               | "  [" + (.alert.severity|tostring) + "] " + .alert.signature
                 + "  src=" + (.src_ip // "?")' 2>/dev/null \
      | sort -u || echo "  (aucune alerte lue — vérifier le chemin $EVE)"
  else
    echo "  $EVE illisible ou jq absent."
    echo "  Relever manuellement : sudo grep -F '\"event_type\":\"alert\"' $EVE | tail"
  fi
  echo
  echo "### Interprétation"
  echo "Conforme si : chaque requête est bloquée (HTTP 000/coupure) ET une"
  echo "alerte de la plage sid 1000001-1000007 apparaît ci-dessus. Une réponse"
  echo "200 sur une de ces URL signifierait que le blocage n'est pas actif :"
  echo "vérifier que Suricata tourne en mode -q 0 et que la file nftables existe."
} 2>&1 | tee "$REPORT"

echo; echo "Rapport : $REPORT"
