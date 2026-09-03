#!/usr/bin/env bash
# Durcissement système commun au serveur et au client — issue #4.
# Usage :  sudo ./harden.sh [--role serveur|client]
#
# Idempotent : rejouable sans effet de bord.

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env

HERE="$(dirname "$(readlink -f "$0")")"
ROLE="serveur"
[ "${1:-}" = "--role" ] && ROLE="${2:-serveur}"

require_vars SSH_PORT
[ "$ROLE" = "serveur" ] && require_vars VPN_SRV_IP

log "=== Durcissement système ($ROLE) ==="

# --- 1. Mises à jour de sécurité automatiques --------------------------------
apt_refresh
apt_install unattended-upgrades apt-listchanges needrestart chrony auditd

write_file /etc/apt/apt.conf.d/20auto-upgrades <<'CFG' || true
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CFG

write_file /etc/apt/apt.conf.d/51unattended-upgrades-local <<'CFG' || true
// Mises à jour de sécurité automatiques — CDC §3.5 « maintien à jour des dépendances ».
// Le redémarrage n'est PAS automatique : il est décidé par l'exploitant, mais
// signalé. Un redémarrage inopiné couperait le tunnel VPN.
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
CFG
systemctl enable --now unattended-upgrades
ok "Mises à jour de sécurité automatiques activées"

# --- 2. Synchronisation horaire ----------------------------------------------
# Indispensable : les codes à usage unique (issues #12 et #17) et la corrélation
# des journaux (issue #28) reposent sur une horloge juste.
systemctl enable --now chrony
ok "Synchronisation horaire active"

# --- 3. Durcissement noyau ---------------------------------------------------
install -D -m 0644 "$HERE/sysctl-hardening.conf" /etc/sysctl.d/99-hardening.conf
sysctl --system >/dev/null
ok "Paramètres noyau appliqués"

# --- 4. SSH ------------------------------------------------------------------
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-$(getent group sudo | cut -d: -f4 | tr ',' ' ')}"
[ -n "$SSH_ALLOW_USERS" ] || die "Aucun utilisateur sudo trouvé — définir SSH_ALLOW_USERS dans .env"

# Sur le client, SSH n'a pas de raison d'écouter : le service est désactivé.
if [ "$ROLE" = "client" ]; then
  systemctl disable --now ssh 2>/dev/null || true
  ok "SSH désactivé sur le poste client"
else
  # Vérification préalable : au moins une clé publique déployée, sinon le
  # passage en « publickey seul » verrouille la machine.
  HAS_KEY=0
  for u in $SSH_ALLOW_USERS; do
    home=$(getent passwd "$u" | cut -d: -f6)
    [ -s "$home/.ssh/authorized_keys" ] && HAS_KEY=1
  done
  [ "$HAS_KEY" -eq 1 ] || die "Aucune clé publique dans authorized_keys pour : $SSH_ALLOW_USERS
       Déployer une clé avant de désactiver l'authentification par mot de passe,
       sinon l'accès SSH sera définitivement perdu."

  write_file /etc/issue.net 0644 <<'BANNER' || true
*******************************************************************************
  Acces restreint. Toute connexion est journalisee et supervisee.
  Les acces non autorises sont interdits et feront l'objet de poursuites.
*******************************************************************************
BANNER

  sed -e "s|@VPN_SRV_IP@|$VPN_SRV_IP|g" \
      -e "s|@SSH_PORT@|$SSH_PORT|g" \
      -e "s|@SSH_ALLOW_USERS@|$SSH_ALLOW_USERS|g" \
      "$HERE/sshd-hardening.conf" > /tmp/99-hardening.conf

  # ListenAddress sur le tunnel : tant que tun0 n'existe pas, sshd ne démarrerait
  # pas. La directive n'est activée qu'une fois le VPN en place (issue #15).
  if ! ip addr show tun0 >/dev/null 2>&1; then
    warn "tun0 absent : ListenAddress commentée pour l'instant."
    warn "Relancer ce script APRÈS l'installation du VPN pour restreindre l'écoute."
    sed -i 's|^ListenAddress|#ListenAddress|' /tmp/99-hardening.conf
  fi

  install -D -m 0600 /tmp/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf
  rm -f /tmp/99-hardening.conf

  sshd -t || die "Configuration sshd invalide — rien n'a été rechargé."
  systemctl reload ssh
  ok "SSH durci (clé uniquement, root interdit, utilisateurs : $SSH_ALLOW_USERS)"
fi

# --- 5. Réduction de la surface d'écoute -------------------------------------
for svc in avahi-daemon cups bluetooth rpcbind; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    systemctl disable --now "$svc" 2>/dev/null && log "Service désactivé : $svc"
  fi
done

# --- 6. Journalisation des appels privilégiés --------------------------------
write_file /etc/audit/rules.d/99-glpi-lab.rules <<'CFG' || true
# Traçabilité des actions privilégiées — CDC §3.4.
-w /etc/passwd -p wa -k identite
-w /etc/shadow -p wa -k identite
-w /etc/sudoers -p wa -k privilege
-w /etc/sudoers.d/ -p wa -k privilege
-w /etc/ssh/sshd_config -p wa -k acces_distant
-w /etc/ssh/sshd_config.d/ -p wa -k acces_distant
-w /etc/nftables.conf -p wa -k pare_feu
-w /etc/openvpn/ -p wa -k vpn
-w /etc/suricata/ -p wa -k ips
-w /etc/glpi/ -p wa -k glpi
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k escalade
CFG
systemctl enable --now auditd 2>/dev/null || true
augenrules --load 2>/dev/null || true
ok "Journalisation d'audit active"

echo
ok "=== Durcissement terminé ($ROLE) ==="
log "Ports en écoute après durcissement :"
ss -tulnp | sed 's/^/    /'
echo
warn "Vérifications manuelles restantes (critères de l'issue #4) :"
warn "  - aucun mot de passe par défaut conservé sur les comptes"
warn "  - écart d'horloge entre les deux machines inférieur à la seconde"
warn "  - tester une connexion SSH par mot de passe : elle doit être refusée"
