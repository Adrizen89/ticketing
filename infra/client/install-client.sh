#!/usr/bin/env bash
# Poste client : VPN, agent d'inventaire, contrôle à distance
# — issues #3, #16, #20, #25.
# Usage :  sudo ./install-client.sh [--profil /chemin/vers/profil.ovpn]

. "$(dirname "$(readlink -f "$0")")/../scripts/lib/common.sh"
require_root
load_env
require_vars GLPI_FQDN VPN_SRV_IP

HERE="$(dirname "$(readlink -f "$0")")"
PROFIL=""
[ "${1:-}" = "--profil" ] && PROFIL="${2:-}"

log "=== Configuration du poste client ==="
apt_refresh

# =============================================================================
# 1. Client VPN — issue #16
# =============================================================================
apt_install openvpn openvpn-systemd-resolved ca-certificates curl

if [ -n "$PROFIL" ]; then
  [ -f "$PROFIL" ] || die "Profil introuvable : $PROFIL"
  install -D -m 0600 -o root -g root "$PROFIL" /etc/openvpn/client/lab.conf
  ok "Profil VPN installé"
  warn "Supprimer la copie d'origine du profil : shred -u $PROFIL"
else
  warn "Aucun profil fourni. Le générer sur le serveur puis relancer :"
  warn "  serveur : sudo ./enroll-client.sh <utilisateur>"
  warn "  client  : sudo ./install-client.sh --profil ~/<utilisateur>.ovpn"
fi

if [ -f /etc/openvpn/client/lab.conf ]; then
  # Le tunnel demande un identifiant et un code TOTP à chaque connexion : il ne
  # peut donc pas démarrer sans intervention. C'est voulu — c'est le principe
  # même du second facteur (issue #17). Le service est activé mais non démarré.
  systemctl enable openvpn-client@lab
  log "Tunnel à monter manuellement : sudo systemctl start openvpn-client@lab"
  log "  ou, pour saisir le code interactivement :"
  log "  sudo openvpn --config /etc/openvpn/client/lab.conf"
fi

# =============================================================================
# 2. Certificat de l'autorité interne
# =============================================================================
# L'agent GLPI vérifie le certificat du serveur : l'autorité interne doit donc
# être connue du poste, sinon la remontée d'inventaire échoue en TLS.
if [ -f "$HERE/glpi-lab-ca.crt" ]; then
  install -D -m 0644 "$HERE/glpi-lab-ca.crt" /usr/local/share/ca-certificates/glpi-lab.crt
  update-ca-certificates >/dev/null
  ok "Autorité interne installée dans le magasin système"
else
  warn "Certificat de l'autorité absent. Le récupérer depuis le serveur :"
  warn "  scp <serveur>:/etc/ssl/glpi/glpi.crt $HERE/glpi-lab-ca.crt"
  warn "puis relancer ce script."
fi

# =============================================================================
# 3. Agent GLPI — issues #20 et #22
# =============================================================================
# Vérification explicite : le cahier de recettes proscrit FusionInventory.
if dpkg -l 2>/dev/null | grep -qi fusioninventory; then
  die "FusionInventory est installé. Le cahier de recettes impose l'inventaire
       natif de GLPI 10. Désinstaller avant de poursuivre :
         apt-get purge fusioninventory-agent"
fi

apt_install glpi-agent
mkdir -p /etc/glpi-agent/conf.d /var/log/glpi-agent
sed -e "s|@GLPI_FQDN@|$GLPI_FQDN|g" "$HERE/glpi-agent.cfg" \
    > /etc/glpi-agent/conf.d/99-lab.cfg
chmod 640 /etc/glpi-agent/conf.d/99-lab.cfg
systemctl enable glpi-agent
ok "Agent GLPI configuré (inventaire natif, sans FusionInventory)"

# =============================================================================
# 4. Contrôle à distance — issue #25
# =============================================================================
# Choix : serveur VNC en écoute sur l'interface du tunnel uniquement.
# Un outil passant par un service tiers (TeamViewer et assimilés) contredirait
# la matrice des flux, qui n'autorise aucune sortie vers un relais externe.
# Ce raisonnement est à reprendre dans la documentation technique (issue #36).
apt_install x11vnc

write_file /etc/systemd/system/x11vnc.service <<UNIT || true
[Unit]
Description=Controle a distance VNC (tunnel VPN uniquement)
After=network-online.target openvpn-client@lab.service
Requires=openvpn-client@lab.service

[Service]
Type=simple
# -localhost desactive : l'ecoute est portee par l'interface du tunnel.
# -rfbauth : authentification obligatoire, jamais de session ouverte.
# -ssl : session chiffree, en plus du chiffrement du tunnel.
# L'ecoute est restreinte par nftables (client.nft) : seul le serveur, et
# seulement par tun0, atteint le port 5900. systemd n'expanse pas les
# variables shell ici, la restriction ne peut donc pas etre portee par ExecStart.
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -shared -rfbauth /etc/x11vnc.pass -ssl SAVE -rfbport 5900 -o /var/log/x11vnc.log
Restart=on-failure
RestartSec=10
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

if [ ! -f /etc/x11vnc.pass ]; then
  warn "Mot de passe VNC non défini. Le créer avant d'activer le service :"
  warn "  sudo x11vnc -storepasswd /etc/x11vnc.pass && sudo chmod 600 /etc/x11vnc.pass"
  warn "  sudo systemctl enable --now x11vnc"
else
  systemctl daemon-reload
  systemctl enable x11vnc
  ok "Service VNC configuré (démarre avec le tunnel)"
fi

# =============================================================================
# 5. Pare-feu du poste
# =============================================================================
log "Application des règles nftables du client"
"$HERE/../reseau/nftables/install-nftables.sh" client || warn "Pare-feu non appliqué"

echo
ok "=== Poste client configuré ==="
log "Séquence de vérification (critères des issues #16, #20, #22) :"
log "  1. Tunnel coupé   : curl -sk --max-time 5 https://$GLPI_FQDN  -> doit ÉCHOUER"
log "  2. Monter le tunnel : sudo systemctl start openvpn-client@lab"
log "  3. Tunnel monté   : curl -sk --max-time 5 https://$GLPI_FQDN  -> doit RÉPONDRE"
log "  4. Inventaire     : sudo glpi-agent --force --debug"
log "  5. Vérifier dans GLPI : Parc > Ordinateurs — une seule entrée, pas de doublon"
