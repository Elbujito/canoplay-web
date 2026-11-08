#!/usr/bin/env bash
# Change les groupes d'un compte existant, sans toucher à son mot de passe :
#   sudo /opt/jeu/groupes_joueur.sh <identifiant> joueurs,equipe
# « equipe » donne accès au portail des docs (https://gamecanoplay.fr/docs/).
set -euo pipefail

IDENT="${1:?usage : groupes_joueur.sh <identifiant> <groupe1,groupe2>}"
GROUPES="${2:?usage : groupes_joueur.sh <identifiant> <groupe1,groupe2>}"
FICHIER="${FICHIER:-/opt/jeu/etat/utilisateurs.yml}"
[[ "$GROUPES" =~ ^[a-z]+(,[a-z]+)*$ ]] || { echo "groupes : noms en minuscules séparés par des virgules"; exit 2; }

python3 - "$FICHIER" "$IDENT" "$GROUPES" <<'PY'
import sys

import yaml

fichier, ident, groupes = sys.argv[1:]
with open(fichier) as f:
    data = yaml.safe_load(f) or {}
users = data.get("users") or {}
if ident not in users:
    sys.exit(f"compte inconnu : {ident} (comptes : {', '.join(sorted(users))})")
users[ident]["groups"] = groupes.split(",")
with open(fichier + ".nouveau", "w") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=True)
PY
cat "$FICHIER.nouveau" > "$FICHIER"   # en place : Docker monte ce fichier précis
rm -f "$FICHIER.nouveau"
echo "compte « $IDENT » : groupes $GROUPES"
if docker inspect authelia >/dev/null 2>&1; then
  docker restart authelia >/dev/null
  for _ in $(seq 1 30); do [ "$(docker inspect -f '{{.State.Health.Status}}' authelia)" = healthy ] && break; sleep 2; done
  echo "Authelia rechargé : $(docker inspect -f '{{.State.Health.Status}}' authelia) (les joueurs connectés se reconnectent)"
fi
