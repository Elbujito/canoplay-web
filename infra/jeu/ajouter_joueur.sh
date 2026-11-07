#!/usr/bin/env bash
# Crée (ou réinitialise) le compte d'un joueur :   sudo /opt/jeu/ajouter_joueur.sh <identifiant> ["Nom affiché"]
# Le mot de passe est demandé deux fois, sans écho ; seule son empreinte argon2id est écrite
# (calculée en local par python3-argon2 : le mot de passe n'apparaît jamais dans la liste des processus).
# Authelia relit le fichier tout seul (watch: true) : aucun redémarrage.
set -euo pipefail

IDENT="${1:?usage : ajouter_joueur.sh <identifiant> [\"Nom affiché\"]}"
NOM="${2:-$IDENT}"
FICHIER="${FICHIER:-/opt/jeu/etat/utilisateurs.yml}"
[[ "$IDENT" =~ ^[a-z0-9._-]{3,32}$ ]] || { echo "identifiant : 3 à 32 caractères parmi a-z 0-9 . _ -"; exit 2; }

read -r -s -p "Mot de passe pour $IDENT (12 caractères minimum) : " MDP; echo
read -r -s -p "Confirmation : " MDP2; echo
[ "$MDP" = "$MDP2" ] || { echo "les deux saisies diffèrent"; exit 1; }
[ "${#MDP}" -ge 12 ] || { echo "trop court"; exit 1; }

MDP="$MDP" python3 - "$FICHIER" "$IDENT" "$NOM" <<'PY'
import os
import sys

import yaml
from argon2 import PasswordHasher

fichier, ident, nom = sys.argv[1:]
# Paramètres recommandés par Authelia pour argon2id : m = 64 Mio, t = 3, p = 4
empreinte = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4,
                           hash_len=32, salt_len=16).hash(os.environ["MDP"])
with open(fichier) as f:
    data = yaml.safe_load(f) or {}
users = data.get("users") or {}
users[ident] = {"displayname": nom, "password": empreinte, "groups": ["joueurs"]}
data["users"] = users
with open(fichier + ".nouveau", "w") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=True)
PY
unset MDP MDP2
mv "$FICHIER.nouveau" "$FICHIER"
echo "compte « $IDENT » enregistré"
