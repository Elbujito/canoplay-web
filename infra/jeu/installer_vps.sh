#!/usr/bin/env bash
# Installation initiale du VPS (Ubuntu 24.04), à lancer UNE fois, en root :
#   sudo ACME_EMAIL=… bash installer_vps.sh "<clé publique SSH de déploiement>"
#
# Idempotent : relançable sans casse. Ne désactive la connexion par mot de passe que si une clé
# d'administration est déjà installée (sinon on s'enfermerait dehors).
set -euo pipefail

CLE_DEPLOIEMENT="${1:?usage : installer_vps.sh \"ssh-ed25519 AAAA… deploiement\"}"
: "${ACME_EMAIL:?définir ACME_EMAIL (e-mail des certificats Let’s Encrypt)}"
DIR=/opt/jeu
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. Système à jour, mises à jour de sécurité automatiques"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get upgrade -yq
apt-get install -yq docker.io ufw unattended-upgrades fail2ban python3-yaml python3-argon2 openssl
# Le nom du paquet de « docker compose » varie selon la version d'Ubuntu (24.04 : docker-compose-v2)
apt-get install -yq docker-compose-v2 || apt-get install -yq docker-compose-plugin
docker compose version >/dev/null || { echo "docker compose introuvable : installer le plugin à la main"; exit 1; }
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now docker fail2ban

echo "== 2. Pare-feu : SSH, HTTP, HTTPS seulement"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "== 3. SSH : clés uniquement (si une clé d'administration existe)"
if compgen -G "/root/.ssh/authorized_keys" >/dev/null || compgen -G "/home/*/.ssh/authorized_keys" >/dev/null; then
  cat > /etc/ssh/sshd_config.d/10-canoplay.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
  systemctl reload ssh
else
  echo "   ⚠ aucune clé d'administration trouvée : connexion par mot de passe laissée active"
fi

echo "== 4. Utilisateur de déploiement : ne peut lancer QUE deployer.sh"
id deploiement >/dev/null 2>&1 || useradd --system --create-home --shell /bin/bash deploiement
usermod -aG docker deploiement
install -d -m 700 -o deploiement -g deploiement /home/deploiement/.ssh
echo "command=\"$DIR/deployer.sh\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $CLE_DEPLOIEMENT" \
  > /home/deploiement/.ssh/authorized_keys
chown deploiement:deploiement /home/deploiement/.ssh/authorized_keys
chmod 600 /home/deploiement/.ssh/authorized_keys

echo "== 5. Fichiers de l'infrastructure dans $DIR"
install -d -m 755 "$DIR" "$DIR/authelia"
install -m 644 "$SRC/docker-compose.yml" "$SRC/Caddyfile" "$DIR/"
install -m 644 "$SRC/authelia/configuration.yml" "$DIR/authelia/"
install -m 755 "$SRC/deployer.sh" "$SRC/ajouter_joueur.sh" "$SRC/groupes_joueur.sh" "$DIR/"
install -d -m 750 -o deploiement -g deploiement "$DIR/etat" "$DIR/etat/caddy"
install -d -m 755 -o deploiement -g deploiement "$DIR/etat/docs" "$DIR/etat/docs/versions"
install -d -m 700 "$DIR/etat/secrets"
[ -f "$DIR/etat/caddy/actif.caddy" ] || { echo 'respond "Le jeu démarre…" 503' > "$DIR/etat/caddy/actif.caddy"; chown deploiement "$DIR/etat/caddy/actif.caddy"; }
[ -f "$DIR/etat/utilisateurs.yml" ] || echo "users: {}" > "$DIR/etat/utilisateurs.yml"
for s in jwt session stockage; do
  [ -s "$DIR/etat/secrets/$s" ] || (umask 077; openssl rand -hex 64 > "$DIR/etat/secrets/$s")
done
[ -f "$DIR/.env" ] || (umask 077; echo "ACME_EMAIL=$ACME_EMAIL" > "$DIR/.env")
if [ ! -f "$DIR/etat/jeu.env" ]; then
  (umask 077; printf 'ANTHROPIC_API_KEY=\n' > "$DIR/etat/jeu.env")
  echo "   ⚠ renseigner la clé Anthropic : sudo nano $DIR/etat/jeu.env"
fi
chown deploiement "$DIR/etat/jeu.env"

echo "== 6. Minuteur : reprend une version mise en attente tous les quarts d'heure"
install -m 644 "$SRC/systemd/jeu-deploiement-en-attente.service" "$SRC/systemd/jeu-deploiement-en-attente.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now jeu-deploiement-en-attente.timer

echo "== 7. Premier compte (Authelia refuse de démarrer sans au moins un compte)"
if ! grep -q 'password:' "$DIR/etat/utilisateurs.yml"; then
  GROUPES=joueurs,equipe "$DIR/ajouter_joueur.sh" "${ADMIN_IDENT:?définir ADMIN_IDENT : identifiant du premier compte}"
fi

echo "== 8. Démarrage de Caddy et Authelia"
docker network inspect jeu >/dev/null 2>&1 || docker network create jeu
(cd "$DIR" && docker compose up -d)

echo
echo "Terminé. Étapes suivantes :"
echo "  1. sudo nano $DIR/etat/jeu.env               (ANTHROPIC_API_KEY=…)"
echo "  2. sudo $DIR/ajouter_joueur.sh <identifiant>  (un compte par joueur invité)"
echo "  3. pousser sur main dans matrix-game : la CI déploie la première version"
