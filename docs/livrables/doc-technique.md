# Documentation technique — Infrastructure GLPI sécurisée

| | |
|---|---|
| **Livrable** | 2 du cahier des charges (CDC §5) |
| **Objet** | Architecture, modèle de données, choix techniques |
| **Référence CDC** | CDC-TICKETING-SEC-001 v1.0 |
| **Statut** | Gabarit — sections « à relever » complétées après montage du lab |

---

## 1. Présentation

Système de ticketing reposant sur GLPI 10, déployé sur une infrastructure
cloisonnée où l'application n'est joignable qu'à travers un tunnel VPN chiffré
et authentifié à deux facteurs. Ce document décrit l'architecture, le modèle de
données et les choix techniques, et justifie chacun d'eux comme l'exige le
CDC §4.2 et §8.

## 2. Architecture

### 2.1 Vue en zones

Reprend le schéma `docs/Projet_GLPI.drawio_1.png`, structuré en quatre zones.

```
   Zone client                Zone sécurité réseau            Zone serveur
┌──────────────────┐      ┌────────────────────────┐    ┌──────────────────────┐
│ Ubuntu 2 Go      │      │ Tunnel OpenVPN         │    │ Ubuntu Server 4 Go   │
│ · agent GLPI 10  │─────▶│   AES-256-GCM          │───▶│ · Apache + PHP       │
│ · client VPN     │      │ · second facteur TOTP  │    │ · GLPI 10 en HTTPS   │
│ · VNC            │      │ · nftables : seul le   │    │ · MariaDB, écoute    │
│                  │      │   VPN entre            │    │   locale uniquement  │
└──────────────────┘      └────────────────────────┘    └──────────────────────┘
                                                                   │
                                                     ┌─────────────▼────────────┐
                                                     │ Zone supervision         │
                                                     │ · Suricata en IPS        │
                                                     │ · Fail2ban               │
                                                     │ · Prometheus + Grafana   │
                                                     └──────────────────────────┘
```

### 2.2 Architecture applicative en couches (CDC §4.1)

GLPI est une application structurée en couches, ce qui satisfait l'exigence de
séparation présentation / logique métier / accès aux données :

- **Présentation** : interface web GLPI, servie par Apache derrière TLS ;
- **Logique métier** : moteur GLPI (règles d'affectation, workflow des statuts,
  habilitations) ;
- **Accès aux données** : couche d'abstraction de GLPI vers MariaDB, sans requête
  SQL directe depuis la présentation.

### 2.3 Chemin d'un flux utilisateur

1. Le poste client monte le tunnel : certificat, puis identifiant + code TOTP.
2. nftables n'autorise que ce tunnel en entrée ; le trafic HTTPS y circule.
3. Suricata inspecte le trafic autorisé et bloque les signatures connues.
4. Apache termine le TLS et sert GLPI depuis `public/`.
5. GLPI applique les habilitations et interroge MariaDB en local.

### 2.4 Écart d'architecture assumé

Le cahier de recettes impose deux machines. Le pare-feu, l'IPS et la supervision
sont donc portés par la VM serveur, faute d'un troisième hôte. Le cloisonnement
reste logique et effectif, mais une architecture de production placerait ces
fonctions sur un équipement dédié en coupure.

## 3. Modèle de données

Le modèle est celui de GLPI 10. Les entités mobilisées par le périmètre :

| Entité GLPI | Rôle |
|---|---|
| `glpi_users`, `glpi_useremails` | Comptes et adresses |
| `glpi_profiles`, `glpi_profiles_users` | Rôles et rattachements |
| `glpi_groups`, `glpi_groups_users` | Groupes de techniciens |
| `glpi_entities` | Cloisonnement des périmètres |
| `glpi_tickets` | Tickets |
| `glpi_itilfollowups`, `glpi_itilsolutions` | Fil de discussion, solutions |
| `glpi_itilcategories` | Catégories |
| `glpi_documents`, `glpi_documents_items` | Pièces jointes |
| `glpi_logs` | Journal d'audit des actions |
| `glpi_computers` et tables d'inventaire | Parc remonté par l'agent |

Le schéma conceptuel détaillé (diagramme entité-association) est à exporter
depuis GLPI et à joindre ici. _À compléter._

## 4. Stack technique et justifications (CDC §4.2)

| Composant | Choix | Version relevée | Justification |
|---|---|---|---|
| Application | GLPI | _à relever_ | Imposé par le cahier de recettes |
| Système | Ubuntu Server / Ubuntu | _à relever_ | Imposé (4 Go serveur, 2 Go client) |
| Serveur web | Apache | _à relever_ | Intégration `.htaccess` de GLPI, modules `ssl`/`headers`/`rewrite` |
| Langage | PHP | _à relever_ | Requis par GLPI |
| Base de données | MariaDB | _à relever_ | Compatible GLPI, écoute locale simple à durcir |
| VPN | OpenVPN | _à relever_ | Voir § 4.1 |
| Second facteur | PAM + TOTP | — | Voir § 4.2 |
| Pare-feu | nftables | — | Successeur d'iptables, syntaxe déclarative rechargeable |
| IPS | Suricata | _à relever_ | Imposé par le cahier de recettes |
| Contrôle à distance | x11vnc | — | Voir § 4.3 |
| Supervision | Prometheus + Grafana | _à relever_ | Grafana imposé par le schéma |

### 4.1 OpenVPN plutôt que WireGuard

Deux exigences cumulatives excluent WireGuard : le schéma impose un tunnel
**AES-256**, que WireGuard ne permet pas de choisir (ChaCha20 uniquement) ; et
le cahier de recettes impose une **double authentification**, dont WireGuard n'a
aucun mécanisme utilisateur. OpenVPN satisfait les deux à la fois.

### 4.2 TOTP par PAM plutôt que FreeRADIUS

Le schéma indique « RADIUS / LDAP + OTP ». La substance de l'exigence est le
second facteur ; PAM avec `pam_google_authenticator` le fournit sans ajouter un
service réseau à durcir et superviser, pour un seul utilisateur sur deux
machines. FreeRADIUS resterait la voie si le lab était étendu à un annuaire.

### 4.3 VNC sur le tunnel plutôt que TeamViewer

La matrice des flux n'autorise aucune sortie vers un relais externe. Un outil
transitant par un service tiers imposerait un flux sortant permanent vers
Internet, en contradiction directe avec la règle « n'autoriser que le tunnel ».
x11vnc écoute sur l'interface du tunnel et rien d'autre.

## 5. Organisation du dépôt

```
infra/
├── reseau/            plan d'adressage, matrice des flux, nftables
├── serveur/           00-durcissement → 70-sauvegarde, un dossier par étape
├── client/            VPN, agent d'inventaire, VNC
├── donnees-fictives/  jeu de données et peuplement
└── scripts/           bibliothèque commune, preuves de sécurité
docs/livrables/        les six livrables du CDC §5
```

Les scripts sont idempotents, échouent tôt, et ne versionnent aucun secret
(voir `infra/README.md`).

## 6. Stratégie de tests (CDC §4.4)

- Preuves de sécurité automatisées : quatre scénarios (voir la matrice de recette
  et le rapport de sécurité).
- Validation de configuration avant rechargement : `nft -c`, `suricata -T`,
  `apache2ctl configtest`, `fail2ban-client -t`, `promtool check`.
- Vérifications intégrées : chaque script contrôle ses propres critères
  d'acceptation en fin d'exécution.

## 7. Exploitation

- **Sauvegarde** : quotidienne, chiffrée AES-256, base + `files/` (`70-sauvegarde/`).
- **Restauration** : vérifie les empreintes et sauvegarde l'état courant avant
  d'écraser.
- **Supervision** : Grafana (via tunnel), alerting sur disponibilité et sécurité.
- **Mises à jour** : automatiques pour la sécurité, sans redémarrage inopiné.
