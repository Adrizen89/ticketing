#!/usr/bin/env bash
# Génère et applique les règles nftables — issue #18.
# Usage :  sudo ./install-nftables.sh serveur | client
#
# Applique les règles avec un filet de sécurité : si la connectivité est perdue,
# les règles précédentes sont restaurées automatiquement au bout de 60 secondes.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env

ROLE="${1:-}"
[ "$ROLE" = "serveur" ] || [ "$ROLE" = "client" ] \
  || die "Usage : $0 serveur|client"

SRC="$(dirname "$(readlink -f "$0")")/${ROLE}.nft"
[ -f "$SRC" ] || die "Modèle introuvable : $SRC"

apt_refresh
apt_install nftables

if [ "$ROLE" = "serveur" ]; then
  require_vars VPN_CIDR VPN_PORT SSH_PORT
  # Interface portant le LAN : celle de la route par défaut.
  LAN_IF="${LAN_IF:-$(ip -o route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')}"
  [ -n "$LAN_IF" ] || die "Impossible de déterminer l'interface LAN — définir LAN_IF dans .env"
  log "Interface LAN retenue : $LAN_IF"
  sed -e "s|@LAN_IF@|$LAN_IF|g" \
      -e "s|@VPN_CIDR@|$VPN_CIDR|g" \
      -e "s|@VPN_PORT@|$VPN_PORT|g" \
      -e "s|@SSH_PORT@|$SSH_PORT|g" "$SRC" > /tmp/ruleset.nft
else
  require_vars VPN_SRV_IP
  sed -e "s|@VPN_SRV_IP@|$VPN_SRV_IP|g" "$SRC" > /tmp/ruleset.nft
fi

log "Validation syntaxique du jeu de règles"
nft -c -f /tmp/ruleset.nft || die "Jeu de règles invalide — rien n'a été appliqué."
ok "Syntaxe valide"

# Filet de sécurité : sauvegarde des règles courantes et restauration différée.
ROLLBACK=/root/nft-rollback-$(date +%s).nft
nft list ruleset > "$ROLLBACK" 2>/dev/null || true
log "Règles actuelles sauvegardées dans $ROLLBACK"

if [ "${ASSUME_YES:-0}" != "1" ]; then
  warn "Les règles vont couper tout accès hors tunnel VPN."
  warn "Restauration automatique dans 60 s si vous ne confirmez pas."
  ( sleep 60; nft -f "$ROLLBACK" 2>/dev/null && logger "nftables : restauration automatique" ) &
  WATCHDOG=$!
fi

nft -f /tmp/ruleset.nft
ok "Règles appliquées"

if [ "${ASSUME_YES:-0}" != "1" ]; then
  if confirm "Connectivité toujours opérationnelle ? Confirmer pour rendre les règles permanentes"; then
    kill "$WATCHDOG" 2>/dev/null || true
  else
    kill "$WATCHDOG" 2>/dev/null || true
    nft -f "$ROLLBACK"
    die "Règles annulées, configuration précédente restaurée."
  fi
fi

# Suricata ajoute une inclusion à /etc/nftables.conf (issue #27). La régénération
# des règles ne doit pas la faire disparaître silencieusement : l'IPS cesserait
# de voir le trafic sans qu'aucune erreur ne soit signalée.
if grep -q 'nftables.d/suricata.nft' /etc/nftables.conf 2>/dev/null; then
  echo 'include "/etc/nftables.d/suricata.nft"' >> /tmp/ruleset.nft
  log "Inclusion Suricata préservée"
  nft -c -f /tmp/ruleset.nft || die "Jeu de règles invalide avec l'inclusion Suricata."
  nft -f /tmp/ruleset.nft
fi

install -D -m 0640 -o root -g root /tmp/ruleset.nft /etc/nftables.conf
rm -f /tmp/ruleset.nft
systemctl enable --now nftables
ok "Règles rendues permanentes et actives au démarrage (/etc/nftables.conf)"

log "État des ports en écoute :"
ss -tulnp | sed 's/^/    /'
