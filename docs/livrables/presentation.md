# Support de présentation au comité projet

| | |
|---|---|
| **Livrable** | 6 du cahier des charges (CDC §5) — 5 % de la recette |
| **Format cible** | Slides (export PDF) |
| **Statut** | Trame — une section = une planche |

> Trame de présentation. À convertir en diapositives (l'outil est libre). La
> démonstration s'appuie exclusivement sur le jeu de données fictif (CDC §8).

---

## Planche 1 — Titre

Infrastructure de ticketing GLPI sécurisée
Groupe · date · membres

## Planche 2 — Contexte et objectifs

- Besoin : un système de ticketing fiable, traçable et sécurisé.
- Deux exigences fortes : cloisonnement de l'accès et conformité sécurité (30 %).
- Périmètre livré : infrastructure GLPI de bout en bout sur deux machines.

## Planche 3 — Architecture en une image

- Schéma des quatre zones (`docs/Projet_GLPI.drawio_1.png`).
- Message clé : **un seul point d'entrée**, le tunnel VPN.

## Planche 4 — Le socle : GLPI

- GLPI 10 sur Ubuntu Server, HTTPS, base en accès local.
- Profils alignés sur les cinq rôles du cahier des charges.
- _Démo : connexion, création et suivi d'un ticket._

## Planche 5 — L'accès sécurisé

- Tunnel OpenVPN AES-256 + second facteur TOTP.
- Pare-feu nftables : seul le VPN entre.
- _Démo : montage du tunnel avec code, accès à GLPI._

## Planche 6 — La détection

- Suricata en IPS : bloque, ne se contente pas d'alerter.
- Fail2ban sur SSH, VPN et connexion GLPI.
- _Démo : requête malveillante bloquée + alerte._

## Planche 7 — L'exploitation

- Agent d'inventaire natif, collecteur de mails, contrôle à distance.
- Supervision Grafana, sauvegardes chiffrées.
- _Démo : inventaire du poste, tableau de bord._

## Planche 8 — Volet sécurité

- Positionnement sur les dix risques du référentiel : tous traités.
- Quatre scénarios de test avec preuve avant / après.
- Renvoi au rapport d'analyse de sécurité.

## Planche 9 — Choix techniques défendus

- OpenVPN (AES-256 + MFA) plutôt que WireGuard.
- TOTP par PAM plutôt qu'un serveur RADIUS dédié.
- VNC sur tunnel plutôt qu'un outil à relais externe.

## Planche 10 — Bilan

- Livré : socle GLPI, accès sécurisé, détection, supervision, 6 livrables.
- Écarts assumés : zones concentrées sur une machine, certificat auto-signé.
- Suites : troisième hôte dédié, Let's Encrypt si exposition, extension annuaire.

## Planche 11 — Déclaration des outils d'assistance (CDC §8)

- Outils d'assistance au développement utilisés et leur périmètre.
- Chaque choix produit est compris et défendable en questions.

## Planche 12 — Questions

Remerciements et échanges.
