# Plan d'adressage et topologie — issue #1

> Gabarit à compléter avec les valeurs réelles du lab, puis à reporter dans
> `infra/.env` sur chaque machine. Toutes les valeurs ci-dessous sont des
> exemples cohérents entre eux, alignés sur `infra/.env.example`.

## Zones

Reprend le découpage du schéma `docs/Projet_GLPI.drawio_1.png`.

| Zone | Contenu | Machine |
|---|---|---|
| Zone client | Poste Ubuntu, agent GLPI, client VPN + MFA, outil de contrôle à distance | VM cliente |
| Zone sécurité réseau | Tunnel VPN chiffré, pare-feu nftables, second facteur OTP | VM serveur (hôte du VPN et du pare-feu) |
| Zone serveur | Apache + PHP, application GLPI, MariaDB en accès local uniquement | VM serveur |
| Zone supervision | Suricata en IPS, Prometheus, Grafana, Fail2ban | VM serveur |

Le lab tient sur deux machines, conformément au cahier de recettes. La zone
sécurité réseau et la zone supervision sont donc portées par la VM serveur :
c'est une contrainte de moyens, à mentionner comme écart dans la documentation
technique. Une infrastructure de production séparerait le pare-feu et l'IPS sur
un équipement distinct.

## Plan d'adressage

| Élément | Valeur d'exemple | Variable |
|---|---|---|
| Réseau LAN du lab | `192.168.56.0/24` | `LAN_CIDR` |
| Serveur GLPI (LAN) | `192.168.56.10` | `SRV_LAN_IP` |
| Client (LAN) | `192.168.56.20` | `CLI_LAN_IP` |
| Réseau du tunnel VPN | `10.8.0.0/24` | `VPN_CIDR` |
| Serveur, côté tunnel | `10.8.0.1` | `VPN_SRV_IP` |
| Client, côté tunnel | `10.8.0.2` | attribué par OpenVPN |
| Nom de service GLPI | `glpi.lab.local` | `GLPI_FQDN` |

Le sous-réseau VPN ne doit chevaucher aucun réseau existant du lab, ni le réseau
de l'hyperviseur. Vérifier avant de figer la valeur.

## Résolution de noms

`GLPI_FQDN` doit résoudre vers l'adresse **du tunnel** (`10.8.0.1`) sur le poste
client, et non vers l'adresse LAN. C'est ce qui garantit que le trafic applicatif
emprunte bien le tunnel. En l'absence de DNS interne, renseigner `/etc/hosts` sur
le client.

## Mode réseau des interfaces virtuelles

À documenter selon l'hyperviseur retenu. Le montage attendu :

- une interface en réseau interne ou hôte-uniquement, portant le LAN du lab ;
- sur le serveur uniquement, une interface avec accès sortant, pour les mises à
  jour, NTP, SMTP et le renouvellement de certificat.

Le client n'a pas besoin d'accès sortant direct une fois le lab monté.
