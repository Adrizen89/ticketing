# Matrice des flux autorisés — issue #1

Cette matrice est la source de vérité des règles nftables
(`infra/reseau/nftables/`). Toute règle du pare-feu doit correspondre à une
ligne ci-dessous ; toute ligne ci-dessous doit être justifiée.

Principe directeur, imposé par le cahier de recettes : **n'autoriser que le
tunnel du VPN en entrée**. Tout le reste de l'exposition passe par le tunnel.

## Flux entrants — serveur GLPI

| # | Source | Destination | Port / protocole | Justification | Interface |
|---|---|---|---|---|---|
| E1 | Tout | Serveur | 1194/udp | Établissement du tunnel VPN. Seul point d'entrée depuis l'extérieur. | LAN |
| E2 | `10.8.0.0/24` | Serveur | 443/tcp | Accès à GLPI en HTTPS. | tun0 |
| E3 | `10.8.0.0/24` | Serveur | 22/tcp | Administration SSH, restreinte au tunnel (issue #19). | tun0 |
| E4 | `10.8.0.0/24` | Serveur | 3000/tcp | Grafana, restreint au tunnel (issue #29). | tun0 |
| E5 | `127.0.0.1` | Serveur | 3306/tcp | MariaDB. Jamais exposée sur une interface réseau (issue #8). | lo |

Aucune autre entrée. Le port 80/tcp n'est **pas** ouvert depuis l'extérieur : la
redirection HTTP vers HTTPS n'est servie qu'aux clients du tunnel.

## Flux entrants — poste client

| # | Source | Destination | Port / protocole | Justification | Interface |
|---|---|---|---|---|---|
| E6 | `10.8.0.1` | Client | 5900/tcp | Prise en main à distance depuis le serveur, via le tunnel uniquement (issue #25). | tun0 |

## Flux sortants — serveur GLPI

| # | Destination | Port / protocole | Justification |
|---|---|---|---|
| S1 | Dépôts de la distribution | 80, 443/tcp | Mises à jour de sécurité. |
| S2 | Serveurs NTP | 123/udp | Synchronisation horaire, nécessaire aux codes à usage unique et à l'exploitation des journaux. |
| S3 | Résolveurs DNS | 53/udp, 53/tcp | Résolution de noms. |
| S4 | `SMTP_HOST` | 587/tcp | Notifications sortantes (issue #24). |
| S5 | `IMAP_HOST` | 993/tcp | Collecteur de mails (issue #23). |
| S6 | Autorité de certification | 443/tcp | Renouvellement du certificat, si `TLS_MODE=letsencrypt`. |
| S7 | `10.8.0.0/24` | 5900/tcp | Prise en main à distance du poste client. |

## Flux sortants — poste client

| # | Destination | Port / protocole | Justification |
|---|---|---|---|
| S8 | `SRV_LAN_IP` | 1194/udp | Montage du tunnel. |
| S9 | `10.8.0.1` | 443/tcp | Accès à GLPI et remontée d'inventaire de l'agent (issue #20). |
| S10 | Dépôts de la distribution | 80, 443/tcp | Mises à jour. Peut être coupé une fois le lab figé. |

## Vérification

La preuve attendue en recette (issue #33, scénario 1) est un balayage de ports du
serveur depuis l'extérieur du tunnel : seul le port 1194/udp doit répondre.

    ./infra/scripts/scan-preuve.sh <ip-serveur>
