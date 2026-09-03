#!/usr/bin/env bash
# Suricata en mode PRÉVENTION — issue #27.
# Usage :  sudo ./install-suricata.sh
#
# Le cahier de recettes demande un IPS, pas un IDS : Suricata doit bloquer, pas
# seulement alerter. Le blocage passe par une file nftables (NFQUEUE).
#
# Filet de sécurité indispensable : la règle nftables porte « flags bypass ».
# Si Suricata s'arrête ou sature, le trafic passe au lieu d'être coupé. Sans ce
# drapeau, un plantage de l'IPS isolerait complètement le serveur.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars LAN_CIDR VPN_CIDR

HERE="$(dirname "$(readlink -f "$0")")"

log "=== Installation de Suricata en mode IPS ==="
apt_refresh
apt_install suricata jq

# --- 1. Jeux de règles -------------------------------------------------------
log "Récupération des jeux de règles"
suricata-update update-sources >/dev/null 2>&1 || true
suricata-update enable-source et/open >/dev/null 2>&1 || true
suricata-update >/dev/null || warn "Mise à jour des règles incomplète — vérifier l'accès sortant"
ok "Jeux de règles à jour"

# --- 2. Règles locales -------------------------------------------------------
install -D -m 0644 "$HERE/local.rules" /var/lib/suricata/rules/local.rules
ok "Règles locales déposées"

# --- 3. Configuration --------------------------------------------------------
backup_once /etc/suricata/suricata.yaml

# HOME_NET doit couvrir le LAN et le tunnel : sans cela, les règles orientées
# « vers $HOME_NET » ne déclenchent jamais.
python3 - "$LAN_CIDR" "$VPN_CIDR" <<'PY'
import re, sys
lan, vpn = sys.argv[1], sys.argv[2]
p = "/etc/suricata/suricata.yaml"
s = open(p).read()
s = re.sub(r'^(\s*)HOME_NET:.*$',
           rf'\1HOME_NET: "[{lan},{vpn}]"', s, count=1, flags=re.M)
# Activer le mode NFQUEUE (IPS) et la file 0.
if 'nfq:' not in s:
    s += '\nnfq:\n  mode: accept\n  fail-open: yes\n'
open(p, "w").write(s)
print("HOME_NET et mode NFQUEUE configurés")
PY

# Inclure local.rules dans la liste des fichiers chargés.
if ! grep -q 'local.rules' /etc/suricata/suricata.yaml; then
  sed -i 's|^rule-files:|rule-files:\n  - local.rules|' /etc/suricata/suricata.yaml
fi

# --- 4. Validation AVANT tout rechargement -----------------------------------
# Le cahier de recettes prévient : « attention aux fichiers de configuration ».
# Une configuration invalide laisse le serveur sans IPS, silencieusement.
log "Validation de la configuration"
suricata -T -c /etc/suricata/suricata.yaml -v 2>&1 | tail -5 | sed 's/^/    /'
suricata -T -c /etc/suricata/suricata.yaml >/dev/null 2>&1 \
  || die "Configuration Suricata invalide — rien n'a été appliqué."
ok "Configuration valide"

# --- 5. Mode IPS : passage du trafic par la file --------------------------------
write_file /etc/systemd/system/suricata.service.d/nfqueue.conf <<'UNIT' || true
# Mode IPS : Suricata lit la file nftables 0 et décide de laisser passer ou non.
[Service]
ExecStart=
ExecStart=/usr/bin/suricata -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid -q 0 -vvv
Restart=on-failure
RestartSec=5
UNIT
systemctl daemon-reload

# Table dédiée, priorité plus basse que le filtrage : le pare-feu décide
# d'abord ce qui entre, Suricata inspecte ensuite ce qui a été autorisé.
write_file /etc/nftables.d/suricata.nft <<'NFT' || true
# Aiguillage du trafic vers Suricata — issue #27.
# « flags bypass » : si Suricata est arrêté, le trafic passe au lieu d'être
# coupé. Sans ce drapeau, un plantage de l'IPS isole le serveur.
table inet suricata {
    chain input {
        type filter hook input priority 10; policy accept;
        ct state new,established,related queue flags bypass to 0
    }
    chain output {
        type filter hook output priority 10; policy accept;
        ct state new,established,related queue flags bypass to 0
    }
}
NFT

if ! grep -q 'nftables.d/suricata.nft' /etc/nftables.conf 2>/dev/null; then
  echo 'include "/etc/nftables.d/suricata.nft"' >> /etc/nftables.conf
  log "Inclusion ajoutée à /etc/nftables.conf"
fi
nft -c -f /etc/nftables.conf || die "Le jeu de règles nftables devient invalide avec Suricata."
nft -f /etc/nftables.conf
ok "Trafic aiguillé vers la file Suricata"

# --- 6. Mise à jour planifiée des règles -------------------------------------
write_file /etc/systemd/system/suricata-update.service <<'UNIT' || true
[Unit]
Description=Mise a jour des regles Suricata
[Service]
Type=oneshot
ExecStart=/usr/bin/suricata-update
ExecStartPost=/bin/systemctl reload suricata
UNIT
write_file /etc/systemd/system/suricata-update.timer <<'UNIT' || true
[Unit]
Description=Mise a jour quotidienne des regles Suricata
[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now suricata-update.timer
systemctl enable --now suricata
sleep 3

systemctl is-active --quiet suricata || die "Suricata n'a pas démarré."
ok "Suricata actif en mode IPS"

echo
log "Vérifications (critères de l'issue #27) :"
suricatasc -c "iface-stat nfq" 2>/dev/null | sed 's/^/    /' || true
log "Règles chargées :"
grep -c . /var/lib/suricata/rules/suricata.rules 2>/dev/null | sed 's/^/    /' || true
echo
warn "Preuve attendue en recette (issue #33, scénario 3) :"
warn "  depuis le client, dans le tunnel :"
warn "    curl -k https://${GLPI_FQDN:-<fqdn>}/install/install.php"
warn "  la requête doit être bloquée, et l'alerte apparaître :"
warn "    jq -r 'select(.event_type==\"alert\") | .alert.signature' /var/log/suricata/eve.json | tail"
