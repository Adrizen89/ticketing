#!/usr/bin/env bash
# Supervision et protection anti-force brute — issues #29, #30, #31.
# Usage :  sudo ./install-supervision.sh

. "$(dirname "$(readlink -f "$0")")/../../scripts/lib/common.sh"
require_root
load_env
require_vars SSH_PORT VPN_PORT VPN_CIDR GRAFANA_ADMIN_PASSWORD

HERE="$(dirname "$(readlink -f "$0")")"

log "=== Supervision, alerting et Fail2ban ==="
apt_refresh
apt_install fail2ban prometheus prometheus-node-exporter \
            prometheus-blackbox-exporter prometheus-alertmanager grafana jq

# =============================================================================
# 1. Fail2ban — issue #31
# =============================================================================
sed -e "s|@SSH_PORT@|$SSH_PORT|g" -e "s|@VPN_PORT@|$VPN_PORT|g" \
    "$HERE/fail2ban/jail-local.conf" > /etc/fail2ban/jail.d/glpi-lab.local
install -D -m 0644 "$HERE/fail2ban/filter-openvpn.conf" /etc/fail2ban/filter.d/openvpn-lab.conf
install -D -m 0644 "$HERE/fail2ban/filter-glpi.conf"    /etc/fail2ban/filter.d/glpi-login.conf

# La prison GLPI a besoin du journal : le créer s'il n'existe pas encore, sinon
# Fail2ban refuse de démarrer.
mkdir -p /var/log/glpi && touch /var/log/glpi/php-errors.log
chown -R www-data:www-data /var/log/glpi

fail2ban-client -t >/dev/null || die "Configuration Fail2ban invalide."
systemctl enable --now fail2ban
systemctl restart fail2ban
ok "Fail2ban actif"

# =============================================================================
# 2. Prometheus et sondes — issue #29
# =============================================================================
mkdir -p /etc/prometheus/rules
install -D -m 0644 "$HERE/prometheus.yml" /etc/prometheus/prometheus.yml
install -D -m 0644 "$HERE/alertes.yml"    /etc/prometheus/rules/glpi-lab.yml

# Les sondes n'écoutent que sur la boucle locale : elles exposent des
# informations détaillées sur le système, elles ne doivent pas être joignables
# depuis le tunnel. CDC §3.2.
write_file /etc/default/prometheus-node-exporter <<'CFG' || true
ARGS="--web.listen-address=127.0.0.1:9100 --collector.systemd --collector.textfile.directory=/var/lib/prometheus/node-exporter"
CFG
write_file /etc/default/prometheus <<'CFG' || true
ARGS="--web.listen-address=127.0.0.1:9090 --storage.tsdb.retention.time=30d"
CFG
write_file /etc/default/prometheus-blackbox-exporter <<'CFG' || true
ARGS="--web.listen-address=127.0.0.1:9115"
CFG
mkdir -p /var/lib/prometheus/node-exporter

promtool check config /etc/prometheus/prometheus.yml >/dev/null \
  || die "Configuration Prometheus invalide."
promtool check rules /etc/prometheus/rules/glpi-lab.yml >/dev/null \
  || die "Règles d'alerte invalides."
systemctl enable --now prometheus prometheus-node-exporter prometheus-blackbox-exporter
ok "Prometheus et sondes actifs, en écoute locale uniquement"

# =============================================================================
# 3. Exporteur de journaux maison — alimente les alertes de sécurité
# =============================================================================
# Prometheus ne sait pas lire des journaux. Ce script produit deux compteurs
# au format textfile, relus par node_exporter : échecs d'authentification et
# alertes Suricata par sévérité.
write_file /usr/local/bin/lab-log-metrics.sh 0755 <<'SCRIPT' || true
#!/usr/bin/env bash
# Compteurs de sécurité pour Prometheus — issue #30.
set -uo pipefail
OUT=/var/lib/prometheus/node-exporter/lab_security.prom
TMP="${OUT}.$$"

# Échecs d'authentification, toutes surfaces confondues.
AUTH=$(journalctl --since "-24h" --no-pager 2>/dev/null \
       | grep -ciE 'authentication failure|Failed password|AUTH_FAILED|Login failed' || echo 0)

{
  echo "# HELP lab_auth_failures_total Echecs d authentification sur 24h"
  echo "# TYPE lab_auth_failures_total counter"
  echo "lab_auth_failures_total ${AUTH}"

  echo "# HELP lab_suricata_alerts_total Alertes Suricata par severite"
  echo "# TYPE lab_suricata_alerts_total counter"
  if [ -r /var/log/suricata/eve.json ]; then
    for sev in 1 2 3; do
      n=$(tail -n 20000 /var/log/suricata/eve.json 2>/dev/null \
          | jq -r --argjson s "$sev" \
              'select(.event_type=="alert" and .alert.severity==$s) | 1' 2>/dev/null | wc -l)
      echo "lab_suricata_alerts_total{severity=\"${sev}\"} ${n:-0}"
    done
  else
    echo 'lab_suricata_alerts_total{severity="1"} 0'
  fi

  echo "# HELP lab_fail2ban_banned Adresses actuellement bannies par prison"
  echo "# TYPE lab_fail2ban_banned gauge"
  for jail in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p' | tr ',' ' '); do
    n=$(fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Currently banned:\s*//p' | head -1)
    echo "lab_fail2ban_banned{jail=\"${jail// /}\"} ${n:-0}"
  done
} > "$TMP"
mv "$TMP" "$OUT"
SCRIPT

write_file /etc/systemd/system/lab-log-metrics.service <<'UNIT' || true
[Unit]
Description=Compteurs de securite pour Prometheus
[Service]
Type=oneshot
ExecStart=/usr/local/bin/lab-log-metrics.sh
UNIT
write_file /etc/systemd/system/lab-log-metrics.timer <<'UNIT' || true
[Unit]
Description=Calcul periodique des compteurs de securite
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now lab-log-metrics.timer
ok "Compteurs de sécurité alimentés toutes les minutes"

# =============================================================================
# 4. Alertmanager — issue #30
# =============================================================================
write_file /etc/prometheus/alertmanager.yml <<CFG || true
route:
  receiver: courriel
  # Regroupement et temporisation : évite la rafale de messages qui finit
  # par être ignorée. Critère « le volume d'alertes en normal reste nul ».
  group_by: ['alertname', 'severite']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h

receivers:
  - name: courriel
    email_configs:
      - to: '${ALERT_EMAIL:-root@localhost}'
        from: 'alertmanager@${GLPI_FQDN:-localhost}'
        smarthost: '${SMTP_HOST:-localhost}:${SMTP_PORT:-587}'
        require_tls: true
        send_resolved: true
CFG
systemctl enable --now prometheus-alertmanager
ok "Alertmanager actif"

# =============================================================================
# 5. Grafana — issue #29
# =============================================================================
# Écoute restreinte au tunnel : Grafana donne une vue complète de
# l'infrastructure, il ne doit pas être exposé au-delà.
write_file /etc/grafana/grafana.ini <<CFG || true
[server]
protocol = http
http_addr = ${VPN_SRV_IP:-127.0.0.1}
http_port = 3000
domain = ${GLPI_FQDN:-localhost}

[security]
admin_user = ${GRAFANA_ADMIN_USER:-admin}
admin_password = ${GRAFANA_ADMIN_PASSWORD}
# Durcissement du cookie de session et de l'affichage — CDC §3.1, §3.3.
cookie_secure = false
cookie_samesite = strict
disable_gravatar = true
content_security_policy = true
strict_transport_security = false

[users]
allow_sign_up = false
allow_org_create = false

[auth.anonymous]
enabled = false

[analytics]
reporting_enabled = false
check_for_updates = false
CFG
chmod 640 /etc/grafana/grafana.ini
chown root:grafana /etc/grafana/grafana.ini

# Source de données et tableau de bord fournis par fichier : le tableau de bord
# est ainsi versionné et réimportable (critère de l'issue #29).
write_file /etc/grafana/provisioning/datasources/prometheus.yml <<'CFG' || true
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
CFG
write_file /etc/grafana/provisioning/dashboards/lab.yml <<'CFG' || true
apiVersion: 1
providers:
  - name: 'lab-glpi'
    folder: 'Lab GLPI'
    type: file
    options:
      path: /var/lib/grafana/dashboards
CFG
mkdir -p /var/lib/grafana/dashboards
install -D -m 0644 "$HERE/grafana/dashboard-glpi.json" /var/lib/grafana/dashboards/glpi.json
chown -R grafana:grafana /var/lib/grafana/dashboards

systemctl enable --now grafana-server
ok "Grafana actif sur http://${VPN_SRV_IP:-127.0.0.1}:3000 (tunnel uniquement)"

echo
log "Vérifications (critères des issues #29, #30, #31) :"
log "Prisons Fail2ban :"
fail2ban-client status 2>/dev/null | sed 's/^/    /'
log "Écoute des services de supervision (aucun ne doit être sur 0.0.0.0) :"
ss -tlnp 2>/dev/null | grep -E ':(3000|9090|9093|9100|9115) ' | sed 's/^/    /'
echo
warn "Contrôle manuel restant : depuis un poste HORS tunnel, Grafana doit être injoignable."
