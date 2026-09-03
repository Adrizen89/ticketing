# Livrables documentaires (CDC §5)

Les six livrables attendus par le cahier des charges. Rédigés en Markdown pour
évoluer avec le code et l'historique Git ; l'export PDF (livrables 2, 3, 4) et
slides (livrable 6) est produit en fin de projet.

| # | Livrable | Fichier | État |
|---|---|---|---|
| 1 | Code source complet | `../../infra/` | Livré (PR #42, #43) |
| 2 | Documentation technique | [`doc-technique.md`](doc-technique.md) | Gabarit |
| 3 | Documentation fonctionnelle | [`doc-fonctionnelle.md`](doc-fonctionnelle.md) | Gabarit |
| 4 | Rapport d'analyse de sécurité | [`rapport-securite.md`](rapport-securite.md) | Gabarit |
| 5 | Guide d'installation | [`guide-installation.md`](guide-installation.md) | Rédigé |
| 6 | Support de présentation | [`presentation.md`](presentation.md) | Trame |

En complément, la [matrice de recette](matrice-recette.md) relie chaque exigence
du cahier de recettes et du CDC §3 à sa réalisation et à sa preuve, et porte
l'auto-évaluation sur les critères pondérés du CDC §7.

## Passage au format imposé

Le CDC demande PDF (2, 3, 4) et slides (6). Depuis le Markdown :

```bash
# PDF
pandoc doc-technique.md -o doc-technique.pdf

# Slides
pandoc -t revealjs -s presentation.md -o presentation.html
```

Les sources Markdown restent la référence versionnée ; les exports en sont dérivés.
