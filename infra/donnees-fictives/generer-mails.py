#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Messages de démonstration pour le collecteur de mails — issues #23 et #32.

Produit des fichiers .eml prêts à être déposés dans la boîte de collecte, ou
envoyés vers elle. Ils servent à prouver le critère de l'issue #23 : « un mail
envoyé à la boîte crée un ticket correctement catégorisé et rattaché ».

Le troisième message vient d'un expéditeur inconnu : il éprouve la règle de
traitement des expéditeurs non reconnus, qui ne doit pas créer de compte
silencieusement.

Toutes les adresses sont en example.invalid (RFC 2606) : aucun message ne peut
atteindre un destinataire réel, même envoyé par erreur (CDC §8).

Usage :
    ./generer-mails.py                       écrit dans ./mails-demo/
    ./generer-mails.py --envoyer             envoie vers la boîte de collecte
"""

import argparse
import os
import sys
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import donnees  # noqa: E402


def construire(m, destinataire):
    msg = EmailMessage()
    expediteur = f"{m['de']}@{donnees.DOMAINE}"
    msg["From"] = expediteur
    msg["To"] = destinataire
    msg["Subject"] = m["sujet"]
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=donnees.DOMAINE)
    # En-tête de traçabilité : permet de retrouver et de purger les messages
    # de démonstration sans toucher aux vrais tickets.
    msg["X-Lab-Jeu-Fictif"] = "oui"
    msg.set_content(m["corps"])
    return msg


def main():
    p = argparse.ArgumentParser(description="Mails de démonstration — issue #23")
    p.add_argument("--sortie", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "mails-demo"))
    p.add_argument("--envoyer", action="store_true",
                   help="envoie vers la boîte de collecte au lieu d'écrire des fichiers")
    args = p.parse_args()

    destinataire = os.environ.get("IMAP_USER", f"support@{donnees.DOMAINE}")

    if args.envoyer:
        import smtplib
        hote = os.environ.get("SMTP_HOST")
        if not hote:
            print("SMTP_HOST non défini — charger le .env avant d'envoyer", file=sys.stderr)
            return 1
        port = int(os.environ.get("SMTP_PORT", "587"))
        with smtplib.SMTP(hote, port, timeout=20) as s:
            s.starttls()   # jamais d'identifiants en clair — CDC §3.3
            if os.environ.get("SMTP_USER"):
                s.login(os.environ["SMTP_USER"], os.environ.get("SMTP_PASSWORD", ""))
            for m in donnees.MAILS_DEMO:
                s.send_message(construire(m, destinataire))
                print(f"envoyé : {m['sujet']}")
        return 0

    os.makedirs(args.sortie, exist_ok=True)
    for i, m in enumerate(donnees.MAILS_DEMO, 1):
        chemin = os.path.join(args.sortie, f"{i:02d}-{m['de'].replace('.', '-')}.eml")
        with open(chemin, "wb") as fh:
            fh.write(construire(m, destinataire).as_bytes())
        print(f"écrit : {chemin}")

    print(f"\nDestinataire : {destinataire}")
    print("Pour éprouver le collecteur :")
    print("  · déposer ces fichiers dans la boîte, ou")
    print("  · ./generer-mails.py --envoyer  (après avoir chargé le .env)")
    print("Puis vérifier dans GLPI qu'un ticket a été créé pour chacun,")
    print("et que l'expéditeur inconnu a été traité selon la règle définie.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
