# -*- coding: utf-8 -*-
"""
Jeu de données fictif pour le lab GLPI — issue #32.

CDC §8 : « Aucune donnée réelle de personnes ne doit être utilisée en
environnement de développement ou de test ; seuls des jeux de données fictifs
sont autorisés. »

Toutes les identités sont inventées. Les adresses utilisent le domaine
« example.invalid », réservé par la RFC 2606 : il ne peut être enregistré par
personne et ne résout nulle part, donc aucun message ne peut partir vers un
destinataire réel par erreur.

Le jeu est déterministe : même contenu à chaque exécution, ce qui rend le
peuplement rejouable et les captures d'écran reproductibles.
"""

DOMAINE = "example.invalid"

# --- Groupes de techniciens ---------------------------------------------------
GROUPES = [
    {"name": "Support N1", "comment": "Premier niveau — prise en charge et qualification"},
    {"name": "Support N2", "comment": "Second niveau — expertise et escalade"},
]

# --- Comptes ------------------------------------------------------------------
# Un compte par profil attendu au CDC §2.1, plus des demandeurs pour alimenter
# les files. Les mots de passe sont volontairement lisibles ici : ce sont des
# comptes de démonstration, refusés en production (voir seed-glpi.py).
UTILISATEURS = [
    # Administration
    {"login": "a.moreau",  "prenom": "Alix",    "nom": "Moreau",
     "profil": "Super-Admin", "groupe": None,
     "commentaire": "Administrateur — gère comptes, rôles et journaux"},
    # Supervision
    {"login": "c.bertin",  "prenom": "Camille", "nom": "Bertin",
     "profil": "Supervisor", "groupe": "Support N2",
     "commentaire": "Superviseur — supervise les files et réaffecte"},
    # Techniciens
    {"login": "n.tanguy",  "prenom": "Noam",    "nom": "Tanguy",
     "profil": "Technician", "groupe": "Support N1",
     "commentaire": "Agent support N1"},
    {"login": "s.oueslati", "prenom": "Sarah",  "nom": "Oueslati",
     "profil": "Technician", "groupe": "Support N1",
     "commentaire": "Agent support N1"},
    {"login": "l.fournier", "prenom": "Loup",   "nom": "Fournier",
     "profil": "Technician", "groupe": "Support N2",
     "commentaire": "Agent support N2"},
    # Demandeurs
    {"login": "m.deschamps", "prenom": "Maël",  "nom": "Deschamps",
     "profil": "Self-Service", "groupe": None, "commentaire": "Utilisateur — comptabilité"},
    {"login": "i.rakoto",  "prenom": "Ines",    "nom": "Rakoto",
     "profil": "Self-Service", "groupe": None, "commentaire": "Utilisateur — logistique"},
    {"login": "t.vasseur", "prenom": "Théo",    "nom": "Vasseur",
     "profil": "Self-Service", "groupe": None, "commentaire": "Utilisateur — atelier"},
]

for u in UTILISATEURS:
    u["email"] = "{}@{}".format(u["login"], DOMAINE)

# --- Catégories ITIL ----------------------------------------------------------
CATEGORIES = [
    "Poste de travail",
    "Poste de travail > Matériel",
    "Poste de travail > Logiciel",
    "Compte et accès",
    "Réseau",
    "Messagerie",
    "Demande de service",
]

# --- Tickets ------------------------------------------------------------------
# Les six statuts GLPI sont couverts, ainsi que les cinq priorités :
#   1 Nouveau · 2 En cours (attribué) · 3 En cours (planifié)
#   4 En attente · 5 Résolu · 6 Clos
# type : 1 = incident, 2 = demande
TICKETS = [
    {
        "titre": "Le poste ne démarre plus après la mise à jour",
        "demandeur": "m.deschamps", "assigne": None, "groupe": "Support N1",
        "categorie": "Poste de travail > Logiciel", "statut": 1,
        "urgence": 4, "impact": 3, "priorite": 4, "type": 1,
        "description": (
            "Bonjour,\n\nDepuis la mise à jour de ce matin, mon poste affiche un écran "
            "noir après la saisie du mot de passe. J'ai essayé de redémarrer deux fois, "
            "sans effet.\n\nJe ne peux plus travailler.\n\nCordialement,\nMaël Deschamps"
        ),
        "suivis": [],
    },
    {
        "titre": "Demande d'accès au dossier partagé Logistique",
        "demandeur": "i.rakoto", "assigne": "n.tanguy", "groupe": "Support N1",
        "categorie": "Compte et accès", "statut": 2,
        "urgence": 2, "impact": 2, "priorite": 2, "type": 2,
        "description": (
            "Bonjour,\n\nJe viens d'arriver au service logistique et je n'ai pas accès "
            "au dossier partagé de l'équipe.\n\nMerci d'avance.\nInes Rakoto"
        ),
        "suivis": [
            ("n.tanguy", "Bonjour, je prends en charge votre demande. "
                         "Je vérifie auprès de votre responsable que l'accès est validé."),
            ("i.rakoto", "Merci, mon responsable est Camille Bertin."),
        ],
    },
    {
        "titre": "Imprimante de l'atelier hors ligne",
        "demandeur": "t.vasseur", "assigne": "s.oueslati", "groupe": "Support N1",
        "categorie": "Poste de travail > Matériel", "statut": 3,
        "urgence": 3, "impact": 3, "priorite": 3, "type": 1,
        "description": (
            "L'imprimante de l'atelier n'apparaît plus dans la liste des périphériques "
            "depuis hier. Le voyant est vert mais rien ne sort."
        ),
        "suivis": [
            ("s.oueslati", "Bonjour, l'imprimante ne répond plus au ping. "
                           "Intervention sur site planifiée demain matin."),
        ],
    },
    {
        "titre": "Lenteur généralisée sur l'application de gestion",
        "demandeur": "m.deschamps", "assigne": "l.fournier", "groupe": "Support N2",
        "categorie": "Réseau", "statut": 4,
        "urgence": 4, "impact": 4, "priorite": 4, "type": 1,
        "description": (
            "L'application met plus de trente secondes à charger chaque écran depuis "
            "lundi. Tout le service est concerné."
        ),
        "suivis": [
            ("l.fournier", "Escalade N2. Les temps de réponse réseau sont normaux, "
                           "la lenteur vient probablement du serveur applicatif."),
            ("l.fournier", "En attente du retour de l'éditeur sur le dimensionnement "
                           "de la base. Ticket mis en attente."),
        ],
    },
    {
        "titre": "Mot de passe oublié — compte bloqué",
        "demandeur": "t.vasseur", "assigne": "n.tanguy", "groupe": "Support N1",
        "categorie": "Compte et accès", "statut": 5,
        "urgence": 3, "impact": 2, "priorite": 3, "type": 1,
        "description": "Mon compte est bloqué après plusieurs tentatives de connexion.",
        "suivis": [
            ("n.tanguy", "Compte débloqué et mot de passe réinitialisé. "
                         "Le changement au premier accès est imposé."),
            ("t.vasseur", "C'est bon, j'ai pu me connecter. Merci."),
        ],
        "solution": (
            "Déblocage du compte après vérification de l'identité du demandeur "
            "auprès de son responsable. Mot de passe réinitialisé avec changement "
            "obligatoire à la première connexion."
        ),
    },
    {
        "titre": "Demande de second écran pour le poste comptabilité",
        "demandeur": "m.deschamps", "assigne": "s.oueslati", "groupe": "Support N1",
        "categorie": "Demande de service", "statut": 6,
        "urgence": 2, "impact": 2, "priorite": 2, "type": 2,
        "description": "Je souhaiterais un second écran pour le travail sur tableur.",
        "suivis": [
            ("s.oueslati", "Demande validée par le responsable. Matériel commandé."),
            ("s.oueslati", "Écran livré et installé ce jour. Ticket clos."),
        ],
        "solution": "Second écran installé et déclaré à l'inventaire.",
    },
    {
        "titre": "Messages en double dans la boîte de réception",
        "demandeur": "i.rakoto", "assigne": "l.fournier", "groupe": "Support N2",
        "categorie": "Messagerie", "statut": 2,
        "urgence": 2, "impact": 2, "priorite": 2, "type": 1,
        "description": "Je reçois chaque message deux fois depuis la semaine dernière.",
        "suivis": [
            ("l.fournier", "Le compte est configuré deux fois sur le client de messagerie. "
                           "Suppression du profil en double en cours."),
        ],
    },
    {
        "titre": "Clavier défectueux — touches qui ne répondent plus",
        "demandeur": "t.vasseur", "assigne": None, "groupe": "Support N1",
        "categorie": "Poste de travail > Matériel", "statut": 1,
        "urgence": 3, "impact": 2, "priorite": 3, "type": 1,
        "description": "Les touches A, Z et E ne répondent plus par intermittence.",
        "suivis": [],
    },
    {
        "titre": "Impossible d'ouvrir les fichiers du tableur partagé",
        "demandeur": "m.deschamps", "assigne": "n.tanguy", "groupe": "Support N1",
        "categorie": "Poste de travail > Logiciel", "statut": 5,
        "urgence": 3, "impact": 3, "priorite": 3, "type": 1,
        "description": "Message « fichier verrouillé par un autre utilisateur » en permanence.",
        "suivis": [
            ("n.tanguy", "Un verrou résiduel bloquait le fichier. Verrou levé."),
        ],
        "solution": "Suppression du fichier de verrou résiduel sur le partage réseau.",
    },
    {
        "titre": "Demande de création de compte pour un nouvel arrivant",
        "demandeur": "c.bertin", "assigne": "n.tanguy", "groupe": "Support N1",
        "categorie": "Compte et accès", "statut": 3,
        "urgence": 3, "impact": 3, "priorite": 3, "type": 2,
        "description": (
            "Nouvel arrivant au service logistique le mois prochain. "
            "Merci de préparer le compte et les accès standard du service."
        ),
        "suivis": [
            ("n.tanguy", "Compte préparé, activation planifiée à la date d'arrivée."),
        ],
    },
    {
        "titre": "Connexion au réseau interrompue plusieurs fois par jour",
        "demandeur": "t.vasseur", "assigne": "l.fournier", "groupe": "Support N2",
        "categorie": "Réseau", "statut": 4,
        "urgence": 4, "impact": 3, "priorite": 4, "type": 1,
        "description": "La connexion tombe environ toutes les deux heures, puis revient seule.",
        "suivis": [
            ("l.fournier", "Analyse des journaux du commutateur en cours. "
                           "En attente d'une fenêtre d'intervention."),
        ],
    },
    {
        "titre": "Le poste ne remonte plus à l'inventaire",
        "demandeur": "c.bertin", "assigne": "l.fournier", "groupe": "Support N2",
        "categorie": "Poste de travail", "statut": 6,
        "urgence": 2, "impact": 3, "priorite": 2, "type": 1,
        "description": "Un poste n'apparaît plus dans le parc depuis une semaine.",
        "suivis": [
            ("l.fournier", "L'agent d'inventaire ne parvenait pas à joindre le serveur : "
                           "le tunnel n'était pas monté au démarrage."),
        ],
        "solution": (
            "Service de l'agent réactivé au démarrage, après le montage du tunnel. "
            "La remontée d'inventaire est de nouveau quotidienne."
        ),
    },
]

# --- Messages de démonstration pour le collecteur de mails --------------------
# Servent à éprouver la création automatique de tickets (issue #23).
MAILS_DEMO = [
    {
        "de": "m.deschamps", "sujet": "Écran qui clignote depuis ce matin",
        "corps": (
            "Bonjour,\n\nMon écran clignote toutes les quelques secondes depuis ce matin.\n"
            "C'est fatigant à la longue.\n\nMerci,\nMaël Deschamps"
        ),
    },
    {
        "de": "i.rakoto", "sujet": "Demande de logiciel de retouche d'image",
        "corps": (
            "Bonjour,\n\nJ'aurais besoin d'un logiciel de retouche d'image pour préparer "
            "les fiches produits.\n\nCordialement,\nInes Rakoto"
        ),
    },
    {
        "de": "inconnu.externe", "sujet": "Question sur votre catalogue",
        "corps": (
            "Bonjour,\n\nJe ne fais pas partie de votre organisation. Ce message sert à "
            "vérifier la règle de traitement des expéditeurs inconnus (issue #23).\n"
        ),
    },
]
