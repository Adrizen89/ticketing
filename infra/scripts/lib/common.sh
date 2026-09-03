#!/usr/bin/env bash
# Bibliothèque commune à tous les scripts d'installation.
# Sourcer en début de script :  . "$(dirname "$0")/../../scripts/lib/common.sh"

set -euo pipefail

C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[0;33m'
C_BLU=$'\033[0;34m'; C_OFF=$'\033[0m'

log()   { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()    { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '%s[ !! ]%s %s\n' "$C_YLW" "$C_OFF" "$*" >&2; }
die()   { printf '%s[ KO ]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Ce script doit être exécuté en root (sudo)."
}

# Charge le fichier .env et vérifie que les variables listées sont renseignées.
# CDC §3.5 : la configuration vient de l'environnement, jamais du code.
load_env() {
  local env_file="${ENV_FILE:-/etc/glpi-lab/.env}"
  [ -f "$env_file" ] || die "Fichier de configuration absent : $env_file (copier infra/.env.example)"

  local perms; perms=$(stat -c '%a' "$env_file")
  [ "$perms" = "600" ] || die "Permissions trop larges sur $env_file ($perms) — attendu 600."

  set -a; . "$env_file"; set +a
  ok "Configuration chargée depuis $env_file"
}

# require_vars VAR1 VAR2 ... — échoue si une variable est vide ou laissée à sa
# valeur d'exemple. Le script refuse de démarrer plutôt que de produire une
# installation à demi configurée.
require_vars() {
  local missing=() placeholder=()
  local v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      missing+=("$v")
    elif [[ "${!v}" == REMPLACER* ]]; then
      placeholder+=("$v")
    fi
  done
  [ ${#missing[@]} -eq 0 ]     || die "Variables non renseignées : ${missing[*]}"
  [ ${#placeholder[@]} -eq 0 ] || die "Variables laissées à leur valeur d'exemple : ${placeholder[*]}"
}

# Sauvegarde un fichier avant modification, une seule fois (première exécution).
backup_once() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -f "${f}.orig" ] && return 0
  cp -a "$f" "${f}.orig"
  log "Sauvegarde de $f -> ${f}.orig"
}

# Installe des paquets seulement s'ils manquent : les scripts sont rejouables.
apt_install() {
  local todo=() p
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || todo+=("$p")
  done
  if [ ${#todo[@]} -gt 0 ]; then
    log "Installation : ${todo[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${todo[@]}"
  fi
}

apt_refresh() {
  log "Mise à jour de l'index des paquets"
  apt-get update -qq
}

# Écrit un fichier uniquement si son contenu change, et signale le changement.
# Retourne 0 si le fichier a été modifié, 1 s'il était déjà à jour — ce qui
# permet à l'appelant de ne recharger un service que quand c'est nécessaire.
# Tout appel doit donc porter « || true », sans quoi set -e interrompt le script
# sur un fichier inchangé.
#
# N'utilise pas « install -D » : la fonction doit échouer bruyamment si
# l'écriture ne passe pas, et rester testable hors d'un système GNU.
write_file() {
  local dest="$1" mode="${2:-0644}" owner="${3:-root:root}"
  local tmp; tmp=$(mktemp)
  cat > "$tmp"

  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"; log "Inchangé : $dest"; return 1
  fi

  backup_once "$dest"
  mkdir -p "$(dirname "$dest")" || { rm -f "$tmp"; die "Répertoire de $dest impossible à créer"; }
  cp "$tmp" "$dest"   || { rm -f "$tmp"; die "Écriture impossible : $dest"; }
  rm -f "$tmp"
  chmod "$mode" "$dest" || die "chmod $mode impossible sur $dest"
  chown "$owner" "$dest" || die "chown $owner impossible sur $dest"
  ok "Écrit : $dest"
  return 0
}

confirm() {
  local prompt="${1:-Continuer ?}"
  [ "${ASSUME_YES:-0}" = "1" ] && return 0
  read -r -p "$prompt [o/N] " r
  [[ "$r" =~ ^[oOyY]$ ]]
}
