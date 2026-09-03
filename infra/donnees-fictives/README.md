# Jeu de données fictif — issue #32

> **CDC §8.** « Aucune donnée réelle de personnes ne doit être utilisée en
> environnement de développement ou de test ; seuls des jeux de données fictifs
> sont autorisés. »

## Contenu

| Fichier | Rôle |
|---|---|
| `donnees.py` | Le jeu lui-même : 8 comptes, 2 groupes, 7 catégories, 12 tickets, 14 suivis, 4 solutions |
| `seed-glpi.py` | Peuplement de GLPI via l'API REST — idempotent, avec `--dry-run` et `--purge` |
| `generer-mails.py` | Messages `.eml` de démonstration pour le collecteur (issue #23) |

Les six statuts GLPI sont couverts — nouveau, en cours attribué, en cours
planifié, en attente, résolu, clos — pour que les indicateurs du tableau de bord
et le calcul du délai moyen de résolution aient de quoi se calculer.

## Pourquoi ces identités sont sûres

Les noms sont inventés. Les adresses utilisent **`example.invalid`**, domaine
réservé par la RFC 2606 : il ne peut être enregistré par personne et ne résout
nulle part. Un message envoyé par erreur depuis le lab n'atteint donc aucun
destinataire réel.

## Garde-fous

`seed-glpi.py` crée des comptes dont le mot de passe est connu de tous ceux qui
lisent le `.env`. Trois refus de démarrer protègent contre un usage hors lab :

1. `LAB_ENVIRONMENT` doit valoir `oui` dans le `.env` ;
2. l'URL cible ne doit pas contenir `prod` ni `production` ;
3. `DEMO_PASSWORD` doit être renseigné, et non laissé à sa valeur d'exemple.

Le critère de l'issue #32 — « les comptes de démonstration sont inutilisables en
production » — est traité en amont : ils ne sont jamais créés ailleurs que sur
le lab, plutôt qu'espérés retirés après coup.

## Prérequis

Une fois dans GLPI :

- **Configuration > Générale > API** : activer l'API REST, créer un client API,
  relever le **jeton d'application** ;
- **Préférences de l'utilisateur** : relever le **jeton d'API personnel**.

Reporter les deux dans `/etc/glpi-lab/.env` (`GLPI_APP_TOKEN`, `GLPI_USER_TOKEN`).

L'API n'est joignable que par le tunnel : monter le VPN avant de lancer le script.

## Utilisation

```bash
# Voir ce qui serait créé, sans rien écrire
./seed-glpi.py --dry-run

# Peupler — rejouable, ne duplique rien
./seed-glpi.py

# Messages de démonstration pour le collecteur
./generer-mails.py                 # écrit des .eml dans mails-demo/
./generer-mails.py --envoyer       # envoie vers la boîte de collecte

# Retirer le jeu fictif
./seed-glpi.py --purge
```

## Limite connue

**L'attribution des profils et des groupes reste manuelle.** L'API GLPI ne la
traite pas de façon fiable d'une version à l'autre ; le script affiche donc la
correspondance attendue et laisse le rattachement à faire dans l'interface.
C'est de toute façon un critère de l'issue #13, qui demande une revue des
habilitations une à une.

| Compte | Profil attendu | Groupe |
|---|---|---|
| `a.moreau` | Super-Admin | — |
| `c.bertin` | Supervisor | Support N2 |
| `n.tanguy` | Technician | Support N1 |
| `s.oueslati` | Technician | Support N1 |
| `l.fournier` | Technician | Support N2 |
| `m.deschamps` | Self-Service | — |
| `i.rakoto` | Self-Service | — |
| `t.vasseur` | Self-Service | — |

Ces trois derniers comptes servent aussi aux tests d'accès croisé du scénario 1
(issue #33) : un demandeur ne doit voir aucun ticket dont il n'est pas l'auteur.
