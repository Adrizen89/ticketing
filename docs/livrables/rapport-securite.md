# Rapport d'analyse de sécurité — Infrastructure GLPI sécurisée

| | |
|---|---|
| **Document** | Livrable 4 du cahier des charges (CDC §5) |
| **Objet** | Système de ticketing GLPI 10 sur infrastructure sécurisée |
| **Référence CDC** | CDC-TICKETING-SEC-001 v1.0 |
| **Statut** | Gabarit à compléter au fil du projet — les sections marquées _à compléter_ attendent les preuves produites lors de la recette |
| **Classification** | Interne |

> Ce document est le squelette du rapport exigé par le CDC. Il est versionné en
> Markdown pour évoluer avec le code ; l'export PDF est produit en fin de projet
> (issue #38). Chaque mesure renvoie à un élément vérifiable du dépôt — script,
> configuration ou issue — comme l'exige le critère d'acceptation.

---

## 1. Synthèse

L'infrastructure met en œuvre un système de ticketing GLPI 10 accessible
uniquement à travers un tunnel VPN chiffré et authentifié à deux facteurs. La
surface exposée se réduit à un seul port ; tout le reste — application, base,
administration, supervision — n'est joignable que par le tunnel. Un système de
détection et de prévention d'intrusion inspecte le trafic autorisé, et une
chaîne de supervision alerte sur les événements de sécurité.

Le critère de sécurité pèse 30 % de la recette (CDC §7). Une faille majeure non
traitée — accès croisé entre comptes, injection, mot de passe en clair — entraîne
le rejet de la recette même si la fonctionnalité répond au besoin (CDC §7, point
de vigilance).

## 2. Périmètre et modèle de menaces

### 2.1 Actifs à protéger

| Actif | Sensibilité | Emplacement |
|---|---|---|
| Données des tickets (descriptions, pièces jointes) | Élevée | Base MariaDB, `files/` |
| Comptes et empreintes de mots de passe | Élevée | Base MariaDB |
| Secrets TOTP et clés VPN | Critique | `/etc/openvpn`, hors dépôt |
| Journaux d'audit et de sécurité | Élevée | Serveur, collecte centralisée |
| Disponibilité du service | Moyenne | Ensemble de la chaîne |

### 2.2 Acteurs de menace considérés

- Attaquant externe sans accès au tunnel — surface réduite au seul port VPN.
- Poste client compromis, disposant d'un accès au tunnel.
- Utilisateur authentifié cherchant à dépasser ses droits (accès croisé, élévation).
- Message piégé arrivant par le collecteur de mails.

### 2.3 Surfaces d'attaque

Port VPN exposé · formulaire de connexion GLPI · collecteur de mails · agent
d'inventaire · service de contrôle à distance · interface d'administration GLPI.

## 3. Architecture de sécurité

Architecture en quatre zones (schéma `docs/Projet_GLPI.drawio_1.png`), portées
par deux machines conformément au cahier de recettes.

```
Client ──[tunnel OpenVPN AES-256 + TOTP]──▶ nftables ──▶ GLPI (HTTPS) ──▶ MariaDB (local)
                                              │                    │
                                         Suricata IPS        Supervision
```

**Écart assumé.** Le pare-feu, l'IPS et la supervision sont hébergés sur la VM
serveur, faute d'une troisième machine. Une architecture de production les
séparerait sur un équipement dédié. Cet écart ne remet pas en cause le
cloisonnement logique, mais concentre les fonctions de sécurité sur un même hôte.

## 4. Couverture des exigences du CDC §3

### 4.1 Authentification (CDC §3.1)

| Exigence | Mesure | Référence | Preuve |
|---|---|---|---|
| Hachage adapté, MD5/SHA1 proscrits | Hachage natif GLPI (bcrypt) ; comptes système en clé SSH, jamais de mot de passe | GLPI, `00-durcissement/` | _à compléter_ |
| Politique de mot de passe côté serveur | Politique GLPI (longueur, complexité) appliquée à la configuration | issue #13 | _à compléter_ |
| Anti-force brute | Fail2ban sur SSH, VPN, connexion GLPI ; règle Suricata de rafale | `60-supervision/fail2ban/`, `50-suricata/local.rules` | Scénario 2 |
| Sessions sécurisées | Cookies `HttpOnly`, `Secure`, `SameSite` | `10-web-php/php-glpi.ini` | _à compléter_ |
| Expiration des sessions | `session.gc_maxlifetime`, `reneg-sec` VPN | `10-web-php/php-glpi.ini`, `40-vpn/server.conf` | _à compléter_ |
| Double authentification | TOTP sur le VPN (PAM) et sur les comptes GLPI | `40-vpn/`, issue #12 | Scénario 4 |

### 4.2 Autorisation (CDC §3.2)

| Exigence | Mesure | Référence | Preuve |
|---|---|---|---|
| Contrôle d'accès par rôle, côté serveur | Profils GLPI alignés sur les cinq rôles ; habilitations revues | issue #13 | _à compléter_ |
| Moindre privilège | Compte base sans GRANT ALL ; agent sans balayage ; comptes VPN sans shell | `20-bdd/`, `client/`, `40-vpn/enroll-client.sh` | _à compléter_ |
| Propriété des ressources (anti-IDOR) | Isolation GLPI par entité et profil ; un demandeur ne voit que ses tickets | issue #13, jeu fictif | Scénario 1 |

### 4.3 Protection des données (CDC §3.3)

| Exigence | Mesure | Référence | Preuve |
|---|---|---|---|
| Validation des entrées | Assurée par GLPI (framework applicatif) | GLPI | _à compléter_ |
| Anti-injection | ORM de GLPI ; MariaDB `local-infile=0`, `secure-file-priv` | `20-bdd/mariadb-glpi.cnf` | Scénario 3 |
| Anti-XSS | Échappement GLPI ; CSP et `X-Content-Type-Options` | `10-web-php/apache-glpi.conf` | _à compléter_ |
| Anti-CSRF | Jeton CSRF de GLPI ; cookies `SameSite` | GLPI, `php-glpi.ini` | _à compléter_ |
| Chiffrement au repos | Secrets TOTP hors dépôt ; sauvegardes chiffrées AES-256 | `40-vpn/`, `70-sauvegarde/backup-glpi.sh` | _à compléter_ |
| Chiffrement en transit | HTTPS obligatoire, TLS 1.2 min, HSTS ; tunnel AES-256-GCM | `10-web-php/`, `40-vpn/server.conf` | _à compléter_ |
| Fichiers déposés | Type et taille contrôlés ; racine sur `public/` ; PHP désactivé dans `files/` | `30-glpi/secure-glpi.sh`, `apache-glpi.conf` | _à compléter_ |

### 4.4 Journalisation et supervision (CDC §3.4)

| Exigence | Mesure | Référence | Preuve |
|---|---|---|---|
| Journalisation des événements sensibles | auditd, journaux GLPI/Apache/VPN/Suricata, collecte centralisée | `00-durcissement/harden.sh`, issue #28 | _à compléter_ |
| Aucun secret dans les journaux | `LogLevel` maîtrisé ; contrôle par recherche ciblée | issue #28 | _à compléter_ |
| Messages d'erreur génériques | `display_errors=Off`, en-têtes de version masqués | `php-glpi.ini`, `apache-glpi.conf` | _à compléter_ |

### 4.5 Configuration et secrets (CDC §3.5)

| Exigence | Mesure | Référence | Preuve |
|---|---|---|---|
| Aucun secret en dur | `.env` hors dépôt ; `.gitignore` ; scan de l'historique | `.gitignore`, `scripts/lib/common.sh` | _à compléter_ |
| Variables d'environnement | Configuration chargée depuis `.env`, validée au démarrage | `scripts/lib/common.sh` | _à compléter_ |
| Séparation des environnements | Garde `LAB_ENVIRONMENT` ; refus si l'URL contient `prod` | `donnees-fictives/seed-glpi.py` | _à compléter_ |
| Dépendances à jour | MAJ de sécurité automatiques ; règles Suricata quotidiennes | `00-durcissement/`, `50-suricata/` | _à compléter_ |

## 5. Positionnement sur le référentiel des dix risques (CDC §3)

> Le CDC impose de se positionner explicitement sur chacun des dix risques :
> les traiter ou justifier leur non-applicabilité. Aucune case ne doit rester
> vide (issue #34).

| # | Risque | Position | Mesures principales | Preuve |
|---|---|---|---|---|
| 1 | Contrôle d'accès défaillant | Traité | RBAC GLPI ; isolation par entité ; VPN en entrée unique | Scénario 1 |
| 2 | Défaillances cryptographiques | Traité | AES-256-GCM (VPN), TLS 1.2+ (HTTPS), AES-256 (sauvegardes), argon2/bcrypt (GLPI) | _à compléter_ |
| 3 | Injection | Traité | ORM GLPI ; durcissement MariaDB ; règles Suricata | Scénario 3 |
| 4 | Conception non sécurisée | Traité | Défense en profondeur : pare-feu + IPS + moindre privilège en couches | _à compléter_ |
| 5 | Mauvaise configuration de sécurité | Traité | `secure-glpi.sh` ; en-têtes ; versions masquées ; comptes par défaut changés | _à compléter_ |
| 6 | Composants vulnérables ou obsolètes | Traité | MAJ auto ; empreinte SHA-256 vérifiée ; inventaire des versions | § 7 |
| 7 | Défaillances d'authentification | Traité | TOTP double facteur ; anti-force brute ; SSH par clé | Scénarios 2, 4 |
| 8 | Défaillances d'intégrité des données | Traité | Vérification d'empreinte à l'installation ; empreintes des sauvegardes | `30-glpi/install-glpi.sh` |
| 9 | Journalisation et supervision insuffisantes | Traité | auditd, collecte centralisée, Prometheus, alerting | _à compléter_ |
| 10 | Falsification de requête côté serveur | Traité | Sortie serveur restreinte par nftables à une liste de destinations ; alerte Suricata sur sortie hors matrice ; agent sans balayage réseau | `reseau/`, `50-suricata/local.rules` |

## 6. Scénarios de test de sécurité (CDC §4.4)

Le CDC exige au moins un scénario documenté avec preuve d'efficacité. Quatre
sont retenus pour couvrir les causes de rejet citées au §7, chacun outillé par
un script produisant une preuve horodatée.

| # | Scénario | Outil | Preuve attendue |
|---|---|---|---|
| 1 | Cloisonnement réseau | `scripts/scan-preuve.sh` | Hors tunnel, seul le port VPN répond |
| 2 | Force brute SSH et GLPI | `tests-securite/scenario2-force-brute.sh` | Bannissement après le seuil |
| 3 | Intrusion applicative | `tests-securite/scenario3-suricata.sh` | Requête bloquée + alerte Suricata |
| 4 | Contournement du second facteur | `tests-securite/scenario4-mfa.sh` | Refus du tunnel sans code TOTP |

Chaque exécution dépose sa sortie dans `tests-securite/preuves/`, à joindre en
annexe de la version PDF. _Résultats à compléter après la recette._

## 7. Inventaire des composants et vulnérabilités

_À compléter à la recette._ Relever la version de chaque composant et vérifier
l'absence de vulnérabilité critique connue non traitée :

| Composant | Version installée | Vulnérabilité critique connue | Traitement |
|---|---|---|---|
| GLPI | _à relever_ | _à vérifier_ | |
| Ubuntu Server | _à relever_ | | |
| Apache / PHP | _à relever_ | | |
| MariaDB | _à relever_ | | |
| OpenVPN | _à relever_ | | |
| Suricata | _à relever_ | | |

## 8. Risques résiduels acceptés

_À compléter._ Recenser ici tout risque non entièrement traité, avec sa
justification et une piste de traitement. Point de départ connu :

- **Concentration des zones sur une machine** — deux machines imposées ;
  atténué par le cloisonnement logique. Piste : troisième hôte dédié.
- **Certificat TLS auto-signé** en lab fermé — atténué par l'import de
  l'autorité interne sur le client. Piste : Let's Encrypt si exposition Internet.

## 9. Conclusion

_À rédiger en fin de projet._ Rappeler le niveau de couverture atteint sur les
exigences du §3, les résultats des quatre scénarios, et les risques résiduels
soumis à l'analyse contradictoire prévue au CDC §8.
