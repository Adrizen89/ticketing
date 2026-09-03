# Infrastructure GLPI sécurisée

Déploiement d'un système de ticketing sur GLPI 10, avec accès distant chiffré et
authentifié à deux facteurs, cloisonnement réseau, détection d'intrusion et
supervision.

## Documents de référence

| Document | Rôle |
|---|---|
| `docs/cahier des recettes.pdf` | Fonctionnalités attendues et leurs priorités |
| `docs/Projet_GLPI.drawio_1.png` | Architecture cible en quatre zones |
| `docs/cahier_des_charges_ticketing_securise.pdf` | Exigences de sécurité, livrables et critères de recette |

## Architecture

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

## Démarrage

Les scripts et configurations sont dans [`infra/`](infra/), avec l'ordre
d'exécution complet : **[infra/README.md](infra/README.md)**.

```bash
sudo mkdir -p /etc/glpi-lab
sudo cp infra/.env.example /etc/glpi-lab/.env
sudo chmod 600 /etc/glpi-lab/.env
sudo nano /etc/glpi-lab/.env          # renseigner les valeurs du lab
```

## Suivi

Le travail est découpé en [41 issues](https://github.com/Adrizen89/ticketing/issues)
réparties sur 7 jalons, de l'environnement réseau aux livrables documentaires.

## Sécurité

Aucun secret n'est versionné (CDC §3.5) : clés, certificats, profils VPN et
fichiers `.env` sont exclus par `.gitignore`. Aucune donnée réelle de personne
n'est utilisée, en développement comme en test (CDC §8).
