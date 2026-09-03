# Matrice de recette et de couverture

| | |
|---|---|
| **Objet** | Système de ticketing GLPI sécurisé |
| **Référence CDC** | CDC-TICKETING-SEC-001 v1.0 |
| **Sources** | Cahier de recettes, cahier des charges §3 et §7 |
| **Statut** | Gabarit — colonne « Résultat » à renseigner à la recette |

> Cette matrice relie chaque exigence à ce qui la réalise — issue, script ou
> configuration — et à la preuve qui la démontre. Elle sert de conducteur à la
> recette et met en évidence tout écart avant la clôture (CDC §8).
>
> Convention **Résultat** : ✅ conforme · ⚠️ partiel · ❌ non conforme · ⏳ à jouer.

---

## 1. Couverture du cahier de recettes

Les dix lignes du tableau du cahier de recettes, dans l'ordre, avec leur priorité.

| # | Fonctionnalité | Priorité | Réalisation | Preuve | Résultat |
|---|---|---|---|---|---|
| R1 | Environnement réseau (2 machines) | Très haute | `reseau/plan-adressage.md`, `reseau/matrice-flux.md` · #1 | Schéma + plan versionnés | ⏳ |
| R2 | Serveur GLPI (Ubuntu, 4 Go) | Haute | `serveur/10-web-php/`, `20-bdd/`, `30-glpi/` · #7, #8, #9 | GLPI joignable en HTTPS | ⏳ |
| R3 | Outil de contrôle à distance | Moyenne | `client/install-client.sh` (VNC sur tunnel) · #25 | Prise en main via tun0 | ⏳ |
| R4 | Collecteur de mails → tickets | Moyenne | issue #23, `donnees-fictives/generer-mails.py` | Mail → ticket créé | ⏳ |
| R5 | Création du client (Ubuntu, 2 Go) | Moyenne | `client/install-client.sh` · #3 | VM cliente opérationnelle | ⏳ |
| R6 | Agent GLPI, inventaire natif | Moyenne | `client/glpi-agent.cfg` · #20, #21, #22 | Poste inventorié, sans doublon | ⏳ |
| R7 | VPN pour se connecter à GLPI | Haute | `serveur/40-vpn/` · #15, #16 | Tunnel AES-256 monté | ⏳ |
| R8 | Pare-feu : seul le VPN en entrée | Haute | `reseau/nftables/` · #18 | Scénario 1 (`scan-preuve.sh`) | ⏳ |
| R9 | Double authentification (MFA) | Haute | `40-vpn/` (TOTP), GLPI 2FA · #12, #17 | Scénario 4 | ⏳ |
| R10 | IPS Suricata | Haute | `serveur/50-suricata/` · #27 | Scénario 3 | ⏳ |

**Éléments du schéma d'architecture non listés au tableau mais implémentés :**

| Élément | Réalisation | Résultat |
|---|---|---|
| Base MySQL/PostgreSQL en accès restreint | `20-bdd/` — écoute locale · #8 | ⏳ |
| HTTPS Let's Encrypt | `10-web-php/` · #11 | ⏳ |
| Monitoring Grafana | `60-supervision/` · #29 | ⏳ |

## 2. Couverture des exigences de sécurité (CDC §3)

| Réf CDC | Exigence | Réalisation | Preuve | Résultat |
|---|---|---|---|---|
| §3.1 | Hachage adapté, MD5/SHA1 proscrits | GLPI (bcrypt), SSH par clé | inspection base | ⏳ |
| §3.1 | Politique de mot de passe serveur | config GLPI · #13 | config | ⏳ |
| §3.1 | Anti-force brute | Fail2ban, Suricata · #31 | Scénario 2 | ⏳ |
| §3.1 | Sessions sécurisées (cookies) | `php-glpi.ini` | en-têtes | ⏳ |
| §3.1 | Expiration sessions/jetons | `php-glpi.ini`, `server.conf` | config | ⏳ |
| §3.1 | Double authentification | TOTP VPN + GLPI · #12, #17 | Scénario 4 | ⏳ |
| §3.2 | RBAC vérifié côté serveur | profils GLPI · #13 | Scénario 1 | ⏳ |
| §3.2 | Moindre privilège | droits base, comptes VPN sans shell | `SHOW GRANTS` | ⏳ |
| §3.2 | Propriété des ressources (anti-IDOR) | entités GLPI · #13 | Scénario 1 | ⏳ |
| §3.3 | Validation des entrées | GLPI | — | ⏳ |
| §3.3 | Anti-injection | ORM GLPI, MariaDB durci | Scénario 3 | ⏳ |
| §3.3 | Anti-XSS + CSP | `apache-glpi.conf` | en-têtes | ⏳ |
| §3.3 | Anti-CSRF | jeton GLPI, `SameSite` | config | ⏳ |
| §3.3 | Chiffrement au repos | sauvegardes AES-256, secrets TOTP | inspection archive | ⏳ |
| §3.3 | Chiffrement en transit | HTTPS TLS 1.2+, tunnel AES-256 | test TLS | ⏳ |
| §3.3 | Fichiers déposés sécurisés | `secure-glpi.sh` | Scénario 3 | ⏳ |
| §3.4 | Journalisation événements sensibles | auditd, collecte · #28 | journaux | ⏳ |
| §3.4 | Aucun secret dans les journaux | recherche ciblée · #28 | grep | ⏳ |
| §3.4 | Messages d'erreur génériques | `php-glpi.ini`, Apache | réponse HTTP | ⏳ |
| §3.5 | Aucun secret en dur | `.gitignore`, `.env` | scan historique | ⏳ |
| §3.5 | Variables d'environnement | `common.sh` | config | ⏳ |
| §3.5 | Séparation des environnements | gardes `seed-glpi.py` | test garde | ✅ |
| §3.5 | Dépendances à jour | MAJ auto, Suricata quotidien | `unattended-upgrades` | ⏳ |

## 3. Référentiel des dix risques (CDC §3)

Renvoi au rapport de sécurité, § 5 : `docs/livrables/rapport-securite.md`.
Les dix risques y sont positionnés, aucun laissé sans traitement ni
justification (#34).

## 4. Cas de recette fonctionnels

Protocoles à jouer sur le lab, avec le jeu de données fictif.

| # | Cas | Rôle | Attendu | Résultat |
|---|---|---|---|---|
| F1 | Connexion via VPN puis GLPI | Demandeur | Accès uniquement tunnel monté + 2FA | ⏳ |
| F2 | Création d'un ticket par le portail | Demandeur | Ticket créé, visible par son auteur seul | ⏳ |
| F3 | Création d'un ticket par mail | — | Mail → ticket catégorisé et rattaché | ⏳ |
| F4 | Expéditeur inconnu au collecteur | — | Traité selon la règle, sans compte silencieux | ⏳ |
| F5 | Prise en charge et suivi | Technicien | Attribution, fil de discussion, changement de statut | ⏳ |
| F6 | Réaffectation d'un ticket | Superviseur | Réaffectation tracée au journal d'audit | ⏳ |
| F7 | Consultation des indicateurs | Superviseur | Délai moyen, volume ouverts/fermés | ⏳ |
| F8 | Remontée d'inventaire | — | Poste inventorié, une seule entrée | ⏳ |
| F9 | Prise en main à distance | Technicien | Session VNC via tunnel uniquement | ⏳ |
| F10 | Administration des comptes | Administrateur | Gestion comptes/rôles, accès aux journaux | ⏳ |

## 5. Cas de recette sécurité

| # | Cas | Script | Attendu | Résultat |
|---|---|---|---|---|
| S1 | Cloisonnement réseau | `scripts/scan-preuve.sh` | Seul le port VPN répond hors tunnel | ⏳ |
| S2 | Force brute | `tests-securite/scenario2-force-brute.sh` | Bannissement après seuil | ⏳ |
| S3 | Intrusion applicative | `tests-securite/scenario3-suricata.sh` | Blocage + alerte Suricata | ⏳ |
| S4 | Contournement 2FA | `tests-securite/scenario4-mfa.sh` | Tunnel refusé sans code TOTP | ⏳ |

## 6. Auto-évaluation sur les critères pondérés (CDC §7)

| Critère | Pondération | Couverture prévue | Auto-note | Justification |
|---|---|---|---|---|
| Fonctionnalités du socle | 25 % | R1–R10 + F1–F10 | ⏳ | à renseigner à la recette |
| Conformité sécurité (§3) | 30 % | § 2 et § 3 ci-dessus + S1–S4 | ⏳ | |
| Qualité du code et de l'architecture | 15 % | scripts idempotents, architecture en couches, historique Git | ⏳ | |
| Complétude de la documentation | 15 % | 6 livrables (§ 7 ci-dessous) | ⏳ | |
| Gestion de projet | 10 % | 41 issues, jalons, journal de bord #41 | ⏳ | |
| Présentation au comité | 5 % | support #40 | ⏳ | |

## 7. État des livrables attendus (CDC §5)

| # | Livrable | Format | Emplacement | État |
|---|---|---|---|---|
| 1 | Code source complet | Dépôt Git | `infra/` | Livré (PR #42, #43) |
| 2 | Documentation technique | PDF | `docs/livrables/doc-technique.md` | Gabarit |
| 3 | Documentation fonctionnelle | PDF | `docs/livrables/doc-fonctionnelle.md` | Gabarit |
| 4 | Rapport d'analyse de sécurité | PDF | `docs/livrables/rapport-securite.md` | Gabarit |
| 5 | Guide d'installation | README | `infra/README.md`, `docs/livrables/guide-installation.md` | Rédigé + gabarit détaillé |
| 6 | Support de présentation | Slides | `docs/livrables/presentation.md` | Gabarit |

## 8. Analyse contradictoire des vulnérabilités (CDC §8)

_À compléter._ Toute vulnérabilité identifiée à la recette est consignée ici,
avec sa gravité, l'analyse contradictoire menée et la décision de clôture.

| Date | Vulnérabilité | Gravité | Analyse | Décision |
|---|---|---|---|---|
| | | | | |
