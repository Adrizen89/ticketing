#!/usr/bin/env bash
# Preuve de cloisonnement réseau — issue #33, scénario 1.
# Usage :  ./scan-preuve.sh <ip-serveur> [--sortie repertoire]
#
# À exécuter DEPUIS L'EXTÉRIEUR DU TUNNEL. Le résultat attendu après l'issue #18 :
# seul le port du VPN répond. Toute autre réponse est un écart à corriger.
#
# Le balayage ne vise que le lab, sur des machines dont vous avez la maîtrise.
# La sortie horodatée est directement versable au rapport de sécurité.

set -uo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "Usage : $0 <ip-serveur> [--sortie repertoire]" >&2; exit 1; }

OUTDIR="./preuves"
[ "${2:-}" = "--sortie" ] && OUTDIR="${3:-./preuves}"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$OUTDIR/scan-$STAMP.txt"

VPN_PORT="${VPN_PORT:-1194}"

{
  echo "==============================================================="
  echo " Preuve de cloisonnement réseau — issue #33, scénario 1"
  echo " Cible   : $TARGET"
  echo " Date    : $(date -Iseconds)"
  echo " Depuis  : $(hostname) — HORS TUNNEL"
  echo "==============================================================="
  echo
  echo "--- Attendu ---------------------------------------------------"
  echo "Un seul port ouvert : ${VPN_PORT}/udp (établissement du tunnel)."
  echo "Tous les autres ports doivent être filtrés, sans réponse."
  echo
  echo "--- Balayage TCP des 1000 ports courants ----------------------"
  if command -v nmap >/dev/null 2>&1; then
    nmap -Pn -T4 --top-ports 1000 --reason "$TARGET" 2>&1
    echo
    echo "--- Balayage UDP des ports d'intérêt --------------------------"
    nmap -Pn -sU -p "$VPN_PORT,53,123,161" --reason "$TARGET" 2>&1
  else
    echo "(nmap absent — repli sur un test de connexion port par port)"
    for p in 22 80 443 3000 3306 5900 8080 9090 9100; do
      if timeout 2 bash -c "</dev/tcp/$TARGET/$p" 2>/dev/null; then
        echo "  $p/tcp   OUVERT   <-- écart à analyser"
      else
        echo "  $p/tcp   filtré"
      fi
    done
  fi

  echo
  echo "--- Contrôles applicatifs, hors tunnel ------------------------"
  for u in "https://$TARGET/" "http://$TARGET/" "http://$TARGET:3000/"; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$u" 2>/dev/null || echo "000")
    if [ "$code" = "000" ]; then
      echo "  $u -> aucune réponse (attendu)"
    else
      echo "  $u -> HTTP $code   <-- ÉCART : service joignable hors tunnel"
    fi
  done

  echo
  echo "--- Interprétation --------------------------------------------"
  echo "Conforme si : ${VPN_PORT}/udp seul répond, et aucune URL ne renvoie"
  echo "autre chose que 000. Sinon, reprendre la matrice des flux"
  echo "(infra/reseau/matrice-flux.md) et les règles nftables."
} | tee "$REPORT"

echo
echo "Rapport écrit : $REPORT"
echo "À joindre au rapport d'analyse de sécurité (issue #38)."
