#!/usr/bin/env bash
# Déploiement bleu/vert du jeu, sans couper une partie en cours.
#
# Appelé de deux façons :
#   1. par la CI, via SSH (forced command) : l'image arrive sur l'entrée standard (docker save | gzip),
#      le tag est dans SSH_ORIGINAL_COMMAND ;
#   2. par le minuteur systemd :  deployer.sh --en-attente   (reprend une version mise en attente).
#
# Règle : on ne bascule que si /sante annonce 0 partie en cours. Sinon la version reste chargée
# et en attente ; le minuteur réessaie tous les quarts d'heure. Si la nouvelle version ne
# démarre pas saine, l'ancienne reste en place (aucune bascule).
set -euo pipefail

DIR="${DIR:-/opt/jeu}"
ETAT="$DIR/etat"
ATTENTE="$ETAT/version_en_attente"
ACTIF="$ETAT/caddy/actif.caddy"
MAX_ATTENTE_H="${MAX_ATTENTE_H:-24}"   # au-delà, on bascule : les parties se reprennent depuis leur sauvegarde
URL_PUBLIQUE="${URL_PUBLIQUE:-https://jeu.canoplay.fr}"

journal() { echo "[$(date -u +%FT%TZ)] $*"; }

exec 9>"$ETAT/deploiement.lock"
flock -n 9 || { journal "un déploiement est déjà en cours"; exit 0; }

couleur_active() { sed -n 's/^reverse_proxy jeu-\([a-z]*\):8765$/\1/p' "$ACTIF" 2>/dev/null; }

parties_en_cours() {  # -1 si le conteneur ne répond pas
  docker exec "jeu-$1" python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('http://127.0.0.1:8765/sante',timeout=3))['parties_en_cours'])" 2>/dev/null || echo -1
}

# --- 1. Recevoir la version -------------------------------------------------
if [ "${1:-}" = "--en-attente" ]; then
  [ -f "$ATTENTE" ] || exit 0
  TAG=$(cat "$ATTENTE")
else
  TAG="${SSH_ORIGINAL_COMMAND:-${1:-}}"
  [[ "$TAG" =~ ^[0-9a-f]{12}$ ]] || { journal "tag refusé : « $TAG »"; exit 2; }
  journal "réception de l'image matrixgame:$TAG"
  gunzip | docker load -q
  docker image inspect "matrixgame:$TAG" >/dev/null
fi

ACTIVE=$(couleur_active)
if [ "$ACTIVE" = bleu ]; then NOUVELLE=vert; else NOUVELLE=bleu; fi

# --- 2. Attendre qu'aucune partie ne tourne --------------------------------
if [ -n "$ACTIVE" ] && docker inspect "jeu-$ACTIVE" >/dev/null 2>&1; then
  N=$(parties_en_cours "$ACTIVE")
  if [ "$N" != 0 ] && [ "$N" != -1 ]; then
    [ -f "$ATTENTE" ] && [ "$(cat "$ATTENTE")" = "$TAG" ] || echo "$TAG" > "$ATTENTE"
    AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$ATTENTE") ) / 3600 ))
    if [ "$AGE_H" -ge "$MAX_ATTENTE_H" ]; then
      journal "attente de ${AGE_H} h dépassée : bascule forcée ($N partie(s) à reprendre depuis « Parties sauvegardées »)"
    else
      journal "EN ATTENTE : $N partie(s) en cours sur jeu-$ACTIVE ; bascule automatique dès qu'elles sont terminées (au plus tard dans $(( MAX_ATTENTE_H - AGE_H )) h)"
      exit 0
    fi
  fi
fi

# --- 3. Démarrer la nouvelle couleur et vérifier sa santé -------------------
docker rm -f "jeu-$NOUVELLE" >/dev/null 2>&1 || true
docker run -d --name "jeu-$NOUVELLE" --network jeu --restart unless-stopped \
  --env-file "$ETAT/jeu.env" -e MATRIXGAME_URL_PUBLIQUE="$URL_PUBLIQUE" \
  -v jeu_parties:/app/parties \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  --memory 1g --pids-limit 256 \
  "matrixgame:$TAG" >/dev/null

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "jeu-$NOUVELLE")" = healthy ] && break
  sleep 2
done
if [ "$(docker inspect -f '{{.State.Health.Status}}' "jeu-$NOUVELLE")" != healthy ]; then
  journal "ÉCHEC : matrixgame:$TAG ne démarre pas sain ; jeu-${ACTIVE:-aucun} reste en ligne"
  docker logs --tail 30 "jeu-$NOUVELLE" 2>&1 | sed 's/^/    /'
  docker rm -f "jeu-$NOUVELLE" >/dev/null
  exit 1
fi

# --- 4. Basculer le proxy, puis arrêter l'ancienne couleur ------------------
echo "reverse_proxy jeu-$NOUVELLE:8765" > "$ACTIF.nouveau"
mv "$ACTIF.nouveau" "$ACTIF"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
if [ -n "$ACTIVE" ]; then docker rm -f "jeu-$ACTIVE" >/dev/null 2>&1 || true; fi
rm -f "$ATTENTE"
echo "$TAG" > "$ETAT/version_en_ligne"
journal "EN LIGNE : matrixgame:$TAG sur jeu-$NOUVELLE"

# Garder les 3 dernières images du jeu
docker images matrixgame --format '{{.CreatedAt}}\t{{.Tag}}' | sort -r | awk -F'\t' 'NR>3{print $2}' \
  | while read -r t; do docker rmi "matrixgame:$t" >/dev/null 2>&1 || true; done
