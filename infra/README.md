# Infrastructure GLPI sécurisée — scripts et configurations

Contenu versionné de l'infrastructure décrite par `docs/cahier des recettes.pdf`
et `docs/Projet_GLPI.drawio_1.png`, sous les contraintes de sécurité de
`docs/cahier_des_charges_ticketing_securise.pdf`.

Chaque script correspond à une ou plusieurs issues du dépôt et vérifie lui-même
ses critères d'acceptation en fin d'exécution.

## Principes appliqués à tous les scripts

- **Idempotents.** Rejouables sans effet de bord. Ils ne réinitialisent jamais
  une base existante ni une autorité de certification déjà créée.
- **Ils échouent tôt.** `set -euo pipefail`, vérification des variables requises,
  validation de configuration avant tout rechargement de service.
- **Aucun secret dans le dépôt** (CDC §3.5). Toute valeur sensible vient de
  `.env`, exclu par `.gitignore`. Les scripts refusent de démarrer si `.env`
  n'est pas en `600` ou si une variable est restée à sa valeur d'exemple.
- **Filet de sécurité sur les opérations risquées.** Les règles nftables se
  restaurent automatiquement au bout de 60 s sans confirmation ; la restauration
  sauvegarde l'état courant avant d'écraser ; Suricata laisse passer le trafic
  s'il tombe, plutôt que d'isoler le serveur.

## Ordre d'exécution

L'ordre suit les dépendances réelles. Le respecter : le pare-feu avant le VPN
couperait l'accès, SSH restreint à `tun0` avant l'existence de `tun0` empêcherait
le service de démarrer.

### Préparation, sur les deux machines

```bash
sudo mkdir -p /etc/glpi-lab && sudo cp infra/.env.example /etc/glpi-lab/.env
sudo chmod 600 /etc/glpi-lab/.env && sudo nano /etc/glpi-lab/.env
```

### Serveur

| Ordre | Commande | Issues |
|---|---|---|
| 1 | `sudo infra/serveur/00-durcissement/harden.sh` | #4 |
| 2 | `sudo infra/serveur/20-bdd/install-mariadb.sh` | #8 |
| 3 | `sudo infra/serveur/10-web-php/install-web-php.sh` | #7, #11 |
| 4 | `sudo infra/serveur/30-glpi/install-glpi.sh` | #9 |
| 5 | `sudo infra/serveur/30-glpi/secure-glpi.sh` | #10 |
| 6 | `sudo infra/serveur/40-vpn/install-openvpn.sh` | #15, #17 |
| 7 | `sudo infra/serveur/40-vpn/enroll-client.sh <utilisateur>` | #16, #17 |
| 8 | `sudo infra/reseau/nftables/install-nftables.sh serveur` | #18 |
| 9 | `sudo infra/serveur/00-durcissement/harden.sh` *(à nouveau)* | #19 |
| 10 | `sudo infra/serveur/50-suricata/install-suricata.sh` | #27 |
| 11 | `sudo infra/serveur/60-supervision/install-supervision.sh` | #29, #30, #31 |
| 12 | `sudo infra/serveur/70-sauvegarde/backup-glpi.sh` | #6, #14 |

L'étape 9 n'est pas une redite : au premier passage `tun0` n'existe pas encore,
le script laisse donc SSH sur toutes les interfaces et le signale. Le second
passage restreint l'écoute au tunnel, une fois le VPN en place.

### Client

```bash
# Sur le serveur, récupérer le profil et le certificat de l'autorité :
scp serveur:/root/vpn-profils/<utilisateur>.ovpn ~/
scp serveur:/etc/ssl/glpi/glpi.crt infra/client/glpi-lab-ca.crt

sudo infra/client/install-client.sh --profil ~/<utilisateur>.ovpn   # #3, #16, #20, #25
```

## Arborescence

```
infra/
├── .env.example                  Modèle de configuration, sans valeur réelle
├── reseau/
│   ├── plan-adressage.md         Topologie et plan d'adressage        (#1)
│   ├── matrice-flux.md           Matrice des flux — source des règles (#1)
│   └── nftables/
│       ├── serveur.nft           Politique drop, seul le VPN en entrée (#18)
│       ├── client.nft            Seul le VNC depuis le serveur         (#18)
│       └── install-nftables.sh   Application avec restauration auto    (#18)
├── serveur/
│   ├── 00-durcissement/          SSH, sysctl, auditd, mises à jour     (#4, #19)
│   ├── 10-web-php/               Apache, TLS, en-têtes, réglages PHP   (#7, #11)
│   ├── 20-bdd/                   MariaDB en écoute locale, droits      (#8)
│   ├── 30-glpi/                  GLPI 10, arborescence séparée, cron   (#9, #10, #26)
│   ├── 40-vpn/                   OpenVPN AES-256, TOTP, révocation     (#15, #16, #17)
│   ├── 50-suricata/              IPS en mode prévention, règles lab    (#27)
│   ├── 60-supervision/           Fail2ban, Prometheus, Grafana         (#29, #30, #31)
│   └── 70-sauvegarde/            Sauvegarde chiffrée et restauration   (#6, #14)
├── client/                       VPN, agent d'inventaire, VNC          (#3, #20, #25)
└── scripts/
    ├── lib/common.sh             Bibliothèque commune
    └── scan-preuve.sh            Preuve de cloisonnement               (#33)
```

## Choix techniques à justifier en soutenance

Le CDC §8 exige que chaque choix puisse être expliqué. Les trois décisions
structurantes prises ici :

**OpenVPN plutôt que WireGuard.** Le schéma d'architecture impose un tunnel
AES-256 ; WireGuard n'implémente que ChaCha20-Poly1305 et ne permet pas de
choisir l'algorithme. Le cahier de recettes impose une double authentification ;
WireGuard n'a aucun mécanisme d'authentification utilisateur, donc aucun second
facteur possible. OpenVPN satisfait les deux exigences simultanément.

**TOTP par PAM plutôt que FreeRADIUS.** Le schéma indique « RADIUS / LDAP + OTP ».
La substance de l'exigence est le second facteur ; PAM avec
`pam_google_authenticator` le fournit sans ajouter un service réseau
supplémentaire à durcir et à superviser. Sur deux machines, un serveur RADIUS
serait une surface d'attaque de plus pour un seul utilisateur. FreeRADIUS reste
la voie à suivre si le lab est étendu à un annuaire.

**VNC en écoute sur le tunnel plutôt que TeamViewer.** La matrice des flux
n'autorise aucune sortie vers un relais externe. Un outil passant par un service
tiers imposerait d'ouvrir un flux sortant permanent vers Internet, ce qui
contredirait la règle « n'autoriser que le tunnel du VPN ».

## Écarts assumés

- **Une seule machine porte quatre zones du schéma.** Le cahier de recettes
  impose deux machines ; le pare-feu, l'IPS et la supervision sont donc sur le
  serveur GLPI. Une architecture de production les séparerait. À mentionner
  dans la documentation technique (#36).
- **`TLS_MODE=selfsigned` par défaut.** Let's Encrypt suppose que le serveur est
  joignable depuis Internet, ce qui contredit la règle du pare-feu. Sur un lab
  fermé, l'autorité interne est le choix cohérent — à justifier (#38).

## Vérifier avant de déclarer terminé

```bash
# Depuis l'extérieur du tunnel — seul 1194/udp doit répondre
./infra/scripts/scan-preuve.sh <ip-serveur>

# Sur le serveur
sudo nft list ruleset | head -40
sudo fail2ban-client status
sudo systemctl is-active apache2 mariadb openvpn-server@server suricata grafana-server
sudo jq -r 'select(.event_type=="alert") | .alert.signature' /var/log/suricata/eve.json | tail
```
