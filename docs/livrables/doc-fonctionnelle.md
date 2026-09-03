# Documentation fonctionnelle — Système de ticketing GLPI

| | |
|---|---|
| **Livrable** | 3 du cahier des charges (CDC §5) |
| **Objet** | Cas d'usage et parcours utilisateurs |
| **Référence CDC** | CDC-TICKETING-SEC-001 v1.0 |
| **Statut** | Gabarit — captures à ajouter depuis le lab peuplé |

> Toutes les captures à insérer proviennent du jeu de données fictif (CDC §8) :
> aucune donnée réelle de personne n'apparaît dans ce document.

---

## 1. Rôles et périmètres (CDC §2.1)

| Rôle CDC | Profil GLPI | Périmètre |
|---|---|---|
| Visiteur | — (non authentifié) | Page de connexion uniquement |
| Client / Utilisateur | Self-Service | Crée et suit ses propres tickets |
| Agent support | Technician | Traite les tickets qui lui sont assignés |
| Superviseur / Manager | Supervisor | Supervise les files, réaffecte, consulte les statistiques |
| Administrateur | Super-Admin | Gère comptes, rôles, paramètres et journaux |

## 2. Parcours de connexion

Le parcours d'accès complet, commun à tous les rôles authentifiés :

1. Sur le poste client, montage du tunnel VPN : identifiant + code TOTP.
2. Une fois le tunnel actif, accès à `https://<fqdn-glpi>`.
3. Connexion GLPI ; pour les profils Superviseur et Administrateur, second
   facteur GLPI exigé.
4. Redirection vers le tableau de bord adapté au profil.

_Captures à insérer : montage du tunnel, page de connexion, saisie du 2FA._

## 3. Cas d'usage

### CU1 — Ouvrir un ticket depuis le portail (Client)

Le client crée un ticket : titre, description, catégorie, priorité, pièces
jointes éventuelles. Le ticket reçoit le statut « Nouveau » et n'est visible que
de son auteur et des agents habilités.

### CU2 — Ouvrir un ticket par mail (collecteur)

Un message envoyé à la boîte de collecte crée automatiquement un ticket,
catégorisé et rattaché au demandeur reconnu par son adresse. Un expéditeur
inconnu est traité selon la règle définie, sans création de compte silencieuse.

### CU3 — Prendre en charge et traiter (Agent)

L'agent s'attribue ou reçoit un ticket, échange via le fil de discussion
horodaté, fait évoluer le statut (En cours, En attente, Résolu), puis apporte
une solution. Les notes internes ne sont pas visibles du demandeur.

### CU4 — Superviser une file (Superviseur)

Le superviseur visualise les files, réaffecte les tickets entre agents ou
groupes, et consulte les indicateurs : délai moyen de résolution, volume de
tickets ouverts et fermés. Toute réaffectation est tracée au journal d'audit.

### CU5 — Prendre la main sur un poste (Agent)

Depuis le serveur et par le tunnel, l'agent ouvre une session de contrôle à
distance sur le poste client pour diagnostiquer un incident. La session est
chiffrée et tracée.

### CU6 — Administrer (Administrateur)

L'administrateur gère les comptes et leurs rôles, paramètre les catégories et
les règles d'affectation, et consulte les journaux d'audit et de sécurité.

## 4. Cycle de vie d'un ticket

```
Nouveau ──▶ En cours (attribué) ──▶ En cours (planifié) ──▶ Résolu ──▶ Clos
                     │                                          ▲
                     └──────────────▶ En attente ──────────────┘
```

Les transitions sont contrôlées par les habilitations du profil. Chaque
changement de statut est horodaté et journalisé, ce qui alimente le calcul du
délai moyen de résolution.

## 5. Matrice écran × rôle

_À compléter avec les captures. Trame :_

| Écran | Visiteur | Client | Agent | Superviseur | Admin |
|---|:-:|:-:|:-:|:-:|:-:|
| Connexion | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mes tickets | — | ✅ | ✅ | ✅ | ✅ |
| Tous les tickets | — | — | file assignée | ✅ | ✅ |
| Création de ticket | — | ✅ | ✅ | ✅ | ✅ |
| Tableau de bord / stats | — | limité | limité | ✅ | ✅ |
| Parc / inventaire | — | — | ✅ | ✅ | ✅ |
| Administration | — | — | — | — | ✅ |
| Journaux d'audit | — | — | — | consultation | ✅ |

## 6. Correspondance avec le cahier de recettes

| Fonctionnalité du cahier de recettes | Cas d'usage |
|---|---|
| Serveur GLPI | CU1, CU3, CU4, CU6 |
| Contrôle à distance | CU5 |
| Collecteur de mails | CU2 |
| Agent / inventaire | CU4 (parc), CU5 |
| VPN + MFA | Parcours de connexion (§ 2) |
