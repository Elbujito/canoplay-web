#!/usr/bin/env bash
# Rejoue en local toute l infrastructure du VPS (Caddy en certificats locaux, Authelia, bleu/vert).
# Usage : infra/jeu/test_local.sh <dossier infra/jeu> <dossier de test jetable> <venv avec pyyaml + argon2-cffi>
# Prérequis : docker, et une image matrixgame:test construite depuis matrix-game (docker build -t matrixgame:test .)
set -uo pipefail
SRC="$1"; T="$2"; VENV="$3"
export PATH="$VENV/bin:$PATH"
nettoyer() {
  docker rm -f jeu-bleu jeu-vert >/dev/null 2>&1
  (cd "$T" 2>/dev/null && docker compose -f docker-compose.yml -f test.override.yml down -v >/dev/null 2>&1)
  docker volume rm jeu_parties >/dev/null 2>&1; docker network rm jeu >/dev/null 2>&1
}
nettoyer; rm -rf "$T"; mkdir -p "$T"
trap nettoyer EXIT
cp -r "$SRC"/. "$T"/
mkdir -p "$T/etat/caddy" "$T/etat/secrets"
echo 'respond "Le jeu démarre…" 503' > "$T/etat/caddy/actif.caddy"
echo "users: {}" > "$T/etat/utilisateurs.yml"
for s in jwt session stockage; do openssl rand -hex 64 > "$T/etat/secrets/$s"; done
echo "ACME_EMAIL=test@example.com" > "$T/.env"
printf 'ANTHROPIC_API_KEY=\nMATRIXGAME_MODELE=mock\n' > "$T/etat/jeu.env"
# Différences de test SEULEMENT : certificats locaux, ports hauts
sed -i '1,3c {\n\temail {$ACME_EMAIL}\n\tlocal_certs\n}' "$T/Caddyfile"
cat > "$T/test.override.yml" <<'EOF'
services:
  caddy:
    ports: !override
      - "127.0.0.1:18443:443"
EOF

ok=0; ko=0
verifier() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1 (attendu « $3 », obtenu « $2 »)"; ko=$((ko+1)); fi; }
R="--resolve gamecanoplay.fr:18443:127.0.0.1 --resolve www.gamecanoplay.fr:18443:127.0.0.1 --resolve auth.gamecanoplay.fr:18443:127.0.0.1 -k -s"

echo "== Compte joueur"
printf 'motdepasse-solide-42\nmotdepasse-solide-42\n' | FICHIER="$T/etat/utilisateurs.yml" bash "$T/ajouter_joueur.sh" florent "Florent" | tail -1
verifier "empreinte argon2id écrite, mot de passe absent du fichier" \
  "$(grep -c 'argon2id' "$T/etat/utilisateurs.yml")/$(grep -c 'motdepasse-solide' "$T/etat/utilisateurs.yml")" "1/0"

echo "== Démarrage de Caddy et Authelia"
docker network create jeu >/dev/null
(cd "$T" && docker compose -f docker-compose.yml -f test.override.yml up -d 2>&1 | tail -1)
sante_auth() { curl $R -o /dev/null -w "%{http_code}" https://auth.gamecanoplay.fr:18443/api/health; }
for _ in $(seq 1 60); do [ "$(sante_auth)" = 200 ] && break; sleep 2; done
[ "$(sante_auth)" = 200 ] || { echo "Authelia ne répond pas"; docker logs authelia 2>&1 | tail -15; exit 1; }
echo "  Authelia prêt (HTTP 200)"

echo "== Déploiement 1 (aucune version en ligne)"
docker tag matrixgame:test matrixgame:aaaaaaaaaaaa
docker save matrixgame:aaaaaaaaaaaa | gzip -1 | SSH_ORIGINAL_COMMAND=aaaaaaaaaaaa DIR="$T" bash "$T/deployer.sh" | tail -1
verifier "couleur active" "$(cat "$T/etat/caddy/actif.caddy")" "reverse_proxy jeu-bleu:8765"

echo "== Authentification"
verifier "jeu sans connexion → redirection vers le portail" \
  "$(curl $R -o /dev/null -w '%{http_code}' https://gamecanoplay.fr:18443/)" "302"
verifier "mauvais mot de passe refusé" \
  "$(curl $R -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{"username":"florent","password":"faux-faux-faux"}' https://auth.gamecanoplay.fr:18443/api/firstfactor)" "401"
J="$T/cookies.txt"
curl $R -c "$J" -o /dev/null -H 'Content-Type: application/json' \
  -d '{"username":"florent","password":"motdepasse-solide-42","keepMeLoggedIn":false}' https://auth.gamecanoplay.fr:18443/api/firstfactor
verifier "jeu après connexion" "$(curl $R -b "$J" -o "$T/accueil.html" -w '%{http_code}' https://gamecanoplay.fr:18443/)" "200"
verifier "c'est bien la page d'accueil du jeu" "$(grep -c 'name="jeton"' "$T/accueil.html" | awk '{print ($1>0)}')" "1"
verifier "/sante jamais servie depuis Internet" "$(curl $R -b "$J" -o /dev/null -w '%{http_code}' https://gamecanoplay.fr:18443/sante)" "404"

verifier "www.gamecanoplay.fr → gamecanoplay.fr" "$(curl $R -o /dev/null -w '%{http_code} %{redirect_url}' https://www.gamecanoplay.fr:18443/x)" "301 https://gamecanoplay.fr/x"

echo "== Une partie démarre, puis une nouvelle version arrive"
JETON=$(sed -n 's/.*name="jeton" value="\([^"]*\)".*/\1/p' "$T/accueil.html" | head -1)
CODE=$(curl $R -b "$J" -o /dev/null -w '%{http_code}' -H 'Origin: https://gamecanoplay.fr:18443' \
  --data-urlencode "jeton=$JETON" --data-urlencode "scenario=grand_nord_multimilieux.yaml" --data-urlencode "role=russie" \
  https://gamecanoplay.fr:18443/creer)
verifier "création de partie à travers le proxy (redirection 303)" "$CODE" "303"
N=$(docker exec jeu-bleu python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('http://127.0.0.1:8765/sante'))['parties_en_cours'])")
verifier "une partie en cours" "$N" "1"
docker tag matrixgame:test matrixgame:bbbbbbbbbbbb
docker save matrixgame:bbbbbbbbbbbb | gzip -1 | SSH_ORIGINAL_COMMAND=bbbbbbbbbbbb DIR="$T" bash "$T/deployer.sh" | tail -1
verifier "pas de bascule pendant la partie" "$(cat "$T/etat/caddy/actif.caddy")" "reverse_proxy jeu-bleu:8765"
verifier "version mise en attente" "$(cat "$T/etat/version_en_attente")" "bbbbbbbbbbbb"
DIR="$T" bash "$T/deployer.sh" --en-attente | tail -1
verifier "le minuteur attend encore" "$(cat "$T/etat/caddy/actif.caddy")" "reverse_proxy jeu-bleu:8765"
echo "   (échéance dépassée simulée : MAX_ATTENTE_H=0)"
MAX_ATTENTE_H=0 DIR="$T" bash "$T/deployer.sh" --en-attente | tail -1
verifier "bascule sur vert" "$(cat "$T/etat/caddy/actif.caddy")" "reverse_proxy jeu-vert:8765"
verifier "ancienne couleur arrêtée" "$(docker ps -q --filter name=jeu-bleu | wc -l)" "0"
verifier "jeu servi par la nouvelle version" "$(curl $R -b "$J" -o /dev/null -w '%{http_code}' https://gamecanoplay.fr:18443/)" "200"
echo "   info : parties proposées à la reprise : $(curl $R -b "$J" -s https://gamecanoplay.fr:18443/ | grep -c reprendre) (une partie n est sauvegardée qu après son premier tour)"

echo "== Version défaillante"
printf 'FROM matrixgame:test\nCMD ["sleep","infinity"]\n' | docker build -q -t matrixgame:cccccccccccc - >/dev/null
docker save matrixgame:cccccccccccc | gzip -1 | SSH_ORIGINAL_COMMAND=cccccccccccc DIR="$T" bash "$T/deployer.sh" 2>&1 | grep -m1 "ÉCHEC"
verifier "version défaillante refusée, vert reste en ligne" "$(cat "$T/etat/caddy/actif.caddy")" "reverse_proxy jeu-vert:8765"
verifier "jeu toujours servi" "$(curl $R -b "$J" -o /dev/null -w '%{http_code}' https://gamecanoplay.fr:18443/)" "200"
echo "== Tag invalide"
echo | SSH_ORIGINAL_COMMAND='x; rm -rf /' DIR="$T" bash "$T/deployer.sh" >/dev/null 2>&1
verifier "commande injectée refusée (code 2)" "$?" "2"

docker rmi matrixgame:aaaaaaaaaaaa matrixgame:bbbbbbbbbbbb matrixgame:cccccccccccc >/dev/null 2>&1
echo; echo "RÉSULTAT : $ok réussi(s), $ko échec(s)"
