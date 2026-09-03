#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Peuplement de GLPI avec un jeu de données fictif — issue #32.

Passe par l'API REST de GLPI plutôt que par des requêtes SQL directes : les
règles métier, les droits et les journaux d'audit s'appliquent normalement, et
le peuplement reste valide d'une version de GLPI à l'autre.

Utilise uniquement la bibliothèque standard : aucune dépendance à installer sur
le serveur, ce qui évite d'ajouter une surface à maintenir (CDC §3.5).

Prérequis, à faire une fois dans GLPI :
    Configuration > Générale > API
      · activer « Activer l'API REST »
      · créer un client API et relever le jeton d'application
    Préférences de l'utilisateur > relever le jeton d'API personnel

Usage :
    ./seed-glpi.py                 peuple (idempotent, rejouable)
    ./seed-glpi.py --dry-run       affiche ce qui serait créé, sans rien écrire
    ./seed-glpi.py --purge         retire les objets créés par ce script
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import donnees  # noqa: E402

# Marqueur apposé sur chaque objet créé. C'est lui qui rend le script
# idempotent et le purge possible sans toucher aux données saisies à la main.
MARQUEUR = "[jeu-fictif-lab]"

C_OK, C_KO, C_INFO, C_WARN, C_OFF = "\033[0;32m", "\033[0;31m", "\033[0;34m", "\033[0;33m", "\033[0m"


def ok(m):   print(f"{C_OK}[ ok ]{C_OFF} {m}")
def info(m): print(f"{C_INFO}[ .. ]{C_OFF} {m}")
def warn(m): print(f"{C_WARN}[ !! ]{C_OFF} {m}", file=sys.stderr)
def die(m):  print(f"{C_KO}[ KO ]{C_OFF} {m}", file=sys.stderr); sys.exit(1)


def charger_env(chemin="/etc/glpi-lab/.env"):
    """Lit le .env sans l'exécuter : une variable ne doit pas pouvoir lancer
    de commande. Les valeurs déjà présentes dans l'environnement priment."""
    if not os.path.isfile(chemin):
        return
    with open(chemin, encoding="utf-8") as fh:
        for ligne in fh:
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            cle, _, val = ligne.partition("=")
            cle, val = cle.strip(), val.strip().strip('"').strip("'")
            os.environ.setdefault(cle, val)


class Glpi:
    """Client minimal de l'API REST de GLPI."""

    def __init__(self, url, app_token, user_token, dry_run=False):
        self.base = url.rstrip("/")
        self.app_token = app_token
        self.user_token = user_token
        self.dry_run = dry_run
        self.session = None

    # -- transport ------------------------------------------------------------
    def _appel(self, methode, chemin, corps=None, params=None):
        url = f"{self.base}/{chemin.lstrip('/')}"
        if params:
            url += "?" + urllib.parse.urlencode(params, doseq=True)

        entetes = {"Content-Type": "application/json", "App-Token": self.app_token}
        entetes["Authorization"] = (
            f"session-token {self.session}" if self.session else f"user_token {self.user_token}"
        )
        if self.session:
            entetes["Session-Token"] = self.session

        donnees_brutes = json.dumps(corps).encode("utf-8") if corps is not None else None
        req = urllib.request.Request(url, data=donnees_brutes, headers=entetes, method=methode)
        try:
            with urllib.request.urlopen(req, timeout=30) as rep:
                brut = rep.read().decode("utf-8")
                return json.loads(brut) if brut else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:400]
            raise RuntimeError(f"{methode} {chemin} -> HTTP {e.code} : {detail}") from None
        except urllib.error.URLError as e:
            raise RuntimeError(
                f"{methode} {chemin} injoignable : {e.reason}\n"
                f"       Le tunnel VPN est-il monté ? GLPI n'est joignable que par tun0."
            ) from None

    # -- session --------------------------------------------------------------
    def ouvrir(self):
        rep = self._appel("GET", "/initSession")
        self.session = rep.get("session_token")
        if not self.session:
            die("Session refusée : vérifier GLPI_APP_TOKEN et GLPI_USER_TOKEN.")
        ok("Session API ouverte")

    def fermer(self):
        if self.session:
            try:
                self._appel("GET", "/killSession")
                ok("Session API fermée")
            except RuntimeError:
                pass
            self.session = None

    # -- objets ---------------------------------------------------------------
    def chercher(self, itemtype, champ, valeur):
        """Recherche exacte sur un champ. Retourne l'identifiant ou None."""
        try:
            rep = self._appel("GET", f"/{itemtype}", params={
                f"searchText[{champ}]": valeur, "range": "0-99",
            })
        except RuntimeError:
            return None
        if isinstance(rep, list):
            for item in rep:
                if str(item.get(champ, "")).strip() == str(valeur).strip():
                    return item.get("id")
        return None

    def creer(self, itemtype, champs, cle_unicite):
        """Crée l'objet s'il n'existe pas déjà. Idempotent."""
        existant = self.chercher(itemtype, cle_unicite, champs[cle_unicite])
        if existant:
            info(f"{itemtype} déjà présent : {champs[cle_unicite]} (id {existant})")
            return existant
        if self.dry_run:
            info(f"[simulation] créerait {itemtype} : {champs[cle_unicite]}")
            return -1
        rep = self._appel("POST", f"/{itemtype}", corps={"input": champs})
        if isinstance(rep, list):
            rep = rep[0] if rep else {}
        ident = rep.get("id")
        if not ident:
            raise RuntimeError(f"Création de {itemtype} sans identifiant retourné : {rep}")
        ok(f"{itemtype} créé : {champs[cle_unicite]} (id {ident})")
        return ident

    def supprimer(self, itemtype, ident):
        if self.dry_run:
            return
        self._appel("DELETE", f"/{itemtype}", corps={"input": {"id": ident},
                                                     "force_purge": True})


def verifier_environnement():
    """Refuse de peupler autre chose qu'un lab.

    Critère de l'issue #32 : « les comptes de démonstration sont inutilisables
    en production ». La garde la plus sûre est de ne jamais les créer ailleurs
    que sur le lab, plutôt que d'espérer les retirer après coup.
    """
    if os.environ.get("LAB_ENVIRONMENT", "").lower() not in ("oui", "yes", "1", "true"):
        die("LAB_ENVIRONMENT n'est pas positionné à « oui » dans le .env.\n"
            "       Ce script crée des comptes de démonstration à mot de passe connu.\n"
            "       Il refuse de s'exécuter sur un environnement non déclaré comme lab.")

    url = os.environ.get("GLPI_URL", "")
    for motif in ("prod", "production"):
        if motif in url.lower():
            die(f"L'URL cible contient « {motif} » : peuplement interdit.")
    ok("Environnement de lab confirmé")


def peupler(api, mdp_demo):
    ids_groupes, ids_users, ids_cats = {}, {}, {}

    # --- Groupes -------------------------------------------------------------
    info("--- Groupes ---")
    for g in donnees.GROUPES:
        ids_groupes[g["name"]] = api.creer("Group", {
            "name": g["name"],
            "comment": f"{g['comment']} {MARQUEUR}",
        }, "name")

    # --- Catégories ----------------------------------------------------------
    info("--- Catégories ITIL ---")
    for chemin in donnees.CATEGORIES:
        feuille = chemin.split(" > ")[-1]
        parent = chemin.split(" > ")[0] if " > " in chemin else None
        champs = {"name": feuille, "comment": MARQUEUR}
        if parent and parent in ids_cats:
            champs["itilcategories_id"] = ids_cats[parent]
        ids_cats[chemin] = api.creer("ITILCategory", champs, "name")

    # --- Utilisateurs --------------------------------------------------------
    info("--- Utilisateurs ---")
    for u in donnees.UTILISATEURS:
        ids_users[u["login"]] = api.creer("User", {
            "name": u["login"],
            "realname": u["nom"],
            "firstname": u["prenom"],
            "password": mdp_demo,
            "password2": mdp_demo,
            "comment": f"{u['commentaire']} {MARQUEUR}",
            "is_active": 1,
        }, "name")
        if not api.dry_run and ids_users[u["login"]] > 0:
            try:
                api.creer("UserEmail", {
                    "users_id": ids_users[u["login"]],
                    "email": u["email"],
                    "is_default": 1,
                }, "email")
            except RuntimeError as e:
                warn(f"Adresse non rattachée pour {u['login']} : {e}")

    warn("Profils et rattachements aux groupes à vérifier dans GLPI :")
    for u in donnees.UTILISATEURS:
        warn(f"    {u['login']:<14} profil {u['profil']:<14} groupe {u['groupe'] or '—'}")
    warn("L'API n'attribue pas les profils de façon fiable d'une version à l'autre :")
    warn("ce contrôle reste manuel, et c'est un critère de l'issue #13.")

    # --- Tickets -------------------------------------------------------------
    info("--- Tickets ---")
    cree = 0
    for t in donnees.TICKETS:
        champs = {
            "name": t["titre"],
            "content": t["description"],
            "status": t["statut"],
            "urgency": t["urgence"],
            "impact": t["impact"],
            "priority": t["priorite"],
            "type": t["type"],
            "_users_id_requester": ids_users.get(t["demandeur"]),
            "itilcategories_id": ids_cats.get(t["categorie"]),
        }
        if t.get("assigne"):
            champs["_users_id_assign"] = ids_users.get(t["assigne"])
        if t.get("groupe"):
            champs["_groups_id_assign"] = ids_groupes.get(t["groupe"])

        tid = api.creer("Ticket", champs, "name")
        if api.dry_run or tid <= 0:
            continue
        cree += 1

        for auteur, texte in t["suivis"]:
            try:
                api._appel("POST", "/ITILFollowup", corps={"input": {
                    "itemtype": "Ticket", "items_id": tid,
                    "content": texte, "users_id": ids_users.get(auteur),
                }})
            except RuntimeError as e:
                warn(f"Suivi non ajouté sur « {t['titre'][:40]} » : {e}")

        if "solution" in t:
            try:
                api._appel("POST", "/ITILSolution", corps={"input": {
                    "itemtype": "Ticket", "items_id": tid, "content": t["solution"],
                }})
            except RuntimeError as e:
                warn(f"Solution non ajoutée sur « {t['titre'][:40]} » : {e}")

    ok(f"{cree} tickets créés avec leurs fils de discussion")


def purger(api):
    warn("Purge des objets portant le marqueur " + MARQUEUR)
    total = 0
    for t in donnees.TICKETS:
        i = api.chercher("Ticket", "name", t["titre"])
        if i:
            api.supprimer("Ticket", i); total += 1
    for u in donnees.UTILISATEURS:
        i = api.chercher("User", "name", u["login"])
        if i:
            api.supprimer("User", i); total += 1
    for c in donnees.CATEGORIES:
        i = api.chercher("ITILCategory", "name", c.split(" > ")[-1])
        if i:
            api.supprimer("ITILCategory", i); total += 1
    for g in donnees.GROUPES:
        i = api.chercher("Group", "name", g["name"])
        if i:
            api.supprimer("Group", i); total += 1
    ok(f"{total} objets purgés")


def main():
    p = argparse.ArgumentParser(description="Peuplement fictif de GLPI — issue #32")
    p.add_argument("--dry-run", action="store_true",
                   help="affiche ce qui serait créé, sans rien écrire")
    p.add_argument("--purge", action="store_true",
                   help="retire les objets créés par ce script")
    p.add_argument("--env", default="/etc/glpi-lab/.env")
    args = p.parse_args()

    charger_env(args.env)
    verifier_environnement()

    manquantes = [v for v in ("GLPI_URL", "GLPI_APP_TOKEN", "GLPI_USER_TOKEN")
                  if not os.environ.get(v)]
    if manquantes:
        die("Variables non renseignées : " + ", ".join(manquantes) +
            "\n       Voir l'en-tête de ce script pour les obtenir dans GLPI.")

    mdp = os.environ.get("DEMO_PASSWORD", "")
    if not args.purge and (not mdp or mdp.startswith("REMPLACER")):
        die("DEMO_PASSWORD non renseigné dans le .env.\n"
            "       Générer une valeur : openssl rand -base64 18")

    api = Glpi(os.environ["GLPI_URL"], os.environ["GLPI_APP_TOKEN"],
               os.environ["GLPI_USER_TOKEN"], dry_run=args.dry_run)
    api.ouvrir()
    try:
        if args.purge:
            purger(api)
        else:
            peupler(api, mdp)
            print()
            ok("=== Peuplement terminé ===")
            warn("Rappels, critères de l'issue #32 :")
            warn("  · toutes les identités sont fictives, domaine example.invalid")
            warn("  · les comptes de démonstration ne doivent jamais exister en production")
            warn("  · le script est rejouable : relancer ne duplique rien")
    finally:
        api.fermer()


if __name__ == "__main__":
    main()
