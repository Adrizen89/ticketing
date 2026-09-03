# Guide d'installation et de déploiement

| | |
|---|---|
| **Livrable** | 5 du cahier des charges (CDC §5) |
| **Objet** | Remonter l'infrastructure de zéro |
| **Statut** | Rédigé — section dépannage à enrichir au fil du montage |

> Ce guide complète `infra/README.md` (ordre d'exécution synthétique). Il donne
> ici la procédure détaillée, la table des variables et la marche à suivre en cas
> de blocage. Aucune valeur de secret réelle n'y figure (CDC §3.5).

---

## 1. Prérequis

| Élément | Minimum | Source |
|---|---|---|
| Hyperviseur | au choix, réseau interne + accès sortant serveur | § 2 |
| VM serveur | Ubuntu Server LTS, 4 Go RAM, 2 vCPU | cahier de recettes |
| VM cliente | Ubuntu (bureau), 2 Go RAM | cahier de recettes |
| Accès | un compte sudo avec clé SSH déployée sur le serveur | issue #4 |

## 2. Préparation réseau

1. Arrêter le plan d'adressage : `infra/reseau/plan-adressage.md`.
2. Vérifier que le sous-réseau VPN ne chevauche aucun réseau existant.
3. S'assurer que `GLPI_FQDN` résout, sur le client, vers l'adresse **du tunnel**
   (renseigner `/etc/hosts` à défaut de DNS interne).

## 3. Configuration commune

Sur **chaque** machine :

```bash
sudo mkdir -p /etc/glpi-lab
sudo cp infra/.env.example /etc/glpi-lab/.env
sudo chmod 600 /etc/glpi-lab/.env
sudo nano /etc/glpi-lab/.env      # renseigner selon la table du § 7
```

Les scripts refusent de démarrer si le fichier n'est pas en `600`, si une
variable requise manque, ou si elle est restée à sa valeur d'exemple.

## 4. Installation du serveur

Dans l'ordre — le respecter, les étapes dépendent les unes des autres :

```bash
sudo infra/serveur/00-durcissement/harden.sh              # #4
sudo infra/serveur/20-bdd/install-mariadb.sh              # #8
sudo infra/serveur/10-web-php/install-web-php.sh          # #7, #11
sudo infra/serveur/30-glpi/install-glpi.sh                # #9
sudo infra/serveur/30-glpi/secure-glpi.sh                 # #10
sudo infra/serveur/40-vpn/install-openvpn.sh              # #15, #17
sudo infra/serveur/40-vpn/enroll-client.sh <utilisateur>  # #16, #17
sudo infra/reseau/nftables/install-nftables.sh serveur    # #18
sudo infra/serveur/00-durcissement/harden.sh              # #19 (2e passage)
sudo infra/serveur/50-suricata/install-suricata.sh        # #27
sudo infra/serveur/60-supervision/install-supervision.sh  # #29, #30, #31
sudo infra/serveur/70-sauvegarde/backup-glpi.sh           # #6, #14
```

Le second passage de `harden.sh` n'est pas une redite : il restreint l'écoute
SSH au tunnel, ce qui n'est possible qu'une fois `tun0` créé par le VPN.

Avant `install-glpi.sh`, renseigner `GLPI_SHA256` : le script refuse de
décompresser une archive dont l'empreinte n'est pas vérifiée. La valeur est sur
la page de publication officielle de la version choisie.

## 5. Installation du client

```bash
# Depuis le serveur, récupérer le profil et l'autorité de certification :
scp serveur:/root/vpn-profils/<utilisateur>.ovpn ~/
scp serveur:/etc/ssl/glpi/glpi.crt infra/client/glpi-lab-ca.crt

sudo infra/client/install-client.sh --profil ~/<utilisateur>.ovpn   # #3, #16, #20, #25
shred -u ~/<utilisateur>.ovpn     # ne pas laisser traîner le profil
```

## 6. Peuplement et vérification

```bash
# Monter le tunnel (identifiant + code TOTP) :
sudo systemctl start openvpn-client@lab

# Peupler GLPI avec le jeu fictif (après activation de l'API, voir README dédié) :
infra/donnees-fictives/seed-glpi.py --dry-run
infra/donnees-fictives/seed-glpi.py

# Preuves de sécurité :
infra/scripts/scan-preuve.sh <ip-serveur>                          # scénario 1
sudo infra/scripts/tests-securite/scenario2-force-brute.sh <ip> <fqdn>
infra/scripts/tests-securite/scenario3-suricata.sh <fqdn>
```

## 7. Table des variables d'environnement

| Variable | Obligatoire | Rôle | Exemple |
|---|:-:|---|---|
| `GLPI_FQDN` | oui | Nom de service GLPI | `glpi.lab.local` |
| `SRV_LAN_IP` / `CLI_LAN_IP` | oui | Adresses LAN | `192.168.56.10` |
| `LAN_CIDR` / `VPN_CIDR` | oui | Réseaux LAN et tunnel | `10.8.0.0/24` |
| `VPN_SUBNET` / `VPN_MASK` / `VPN_SRV_IP` | oui | Réseau du tunnel | `10.8.0.0` |
| `VPN_PORT` / `VPN_PROTO` | oui | Écoute VPN | `1194` / `udp` |
| `SSH_PORT` | oui | Port SSH | `22` |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | oui | Base GLPI | — |
| `DB_ROOT_PASSWORD` | oui | Sécurisation initiale MariaDB | — |
| `GLPI_VERSION` / `GLPI_SHA256` | oui | Version et empreinte | `10.0.x` |
| `GLPI_CODE_DIR` / `_CONFIG_DIR` / `_VAR_DIR` / `_LOG_DIR` | oui | Arborescence séparée | `/var/www/glpi` |
| `TLS_MODE` / `TLS_EMAIL` | oui | Certificat | `selfsigned` |
| `SMTP_*` / `IMAP_*` | si collecteur | Messagerie | — |
| `BACKUP_DIR` / `_RETENTION_DAYS` / `_PASSPHRASE` | oui | Sauvegardes | — |
| `GRAFANA_ADMIN_*` / `ALERT_EMAIL` | oui | Supervision | — |
| `LAB_ENVIRONMENT` | pour le peuplement | Garde anti-production | `oui` |
| `GLPI_URL` / `GLPI_APP_TOKEN` / `GLPI_USER_TOKEN` / `DEMO_PASSWORD` | pour le peuplement | API et jeu fictif | — |

## 8. Sauvegarde et restauration

```bash
sudo infra/serveur/70-sauvegarde/backup-glpi.sh              # sauvegarde manuelle
# planifier : installer backup.service + backup.timer (voir 70-sauvegarde/)
sudo infra/serveur/70-sauvegarde/restore-glpi.sh --list     # lister
sudo infra/serveur/70-sauvegarde/restore-glpi.sh <horodatage>
```

Réaliser au moins une restauration complète et en consigner le déroulé (#6).

## 9. Dépannage

_À enrichir avec les blocages réellement rencontrés (critère #39)._

| Symptôme | Piste |
|---|---|
| Un script refuse de démarrer | `.env` en `600` ? variable manquante ou à sa valeur d'exemple ? |
| `install-glpi.sh` s'arrête sur l'empreinte | `GLPI_SHA256` correspond-il à `GLPI_VERSION` ? |
| Apache ne démarre pas | `apache2ctl configtest` ; certificat présent ? |
| Le tunnel ne monte pas | code TOTP correct ? `journalctl -u openvpn-server@server` |
| GLPI injoignable | tunnel monté ? `nft list ruleset` ; `systemctl status apache2` |
| L'agent ne remonte pas | tunnel actif au démarrage ? autorité importée sur le client ? |
| Suricata coupe du trafic légitime | affiner `local.rules` ; `suricata -T` puis recharger |
