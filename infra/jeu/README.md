# Hébergement du matrix game — `gamecanoplay.fr`

Le jeu (dépôt `FlorentHennart/matrix-game`) tourne sur un VPS, derrière une connexion par identifiant.
Son code reste dans son dépôt : ce dossier ne contient que l'infrastructure.

```
Internet ──443──▶ Caddy (HTTPS automatique)
                    ├── auth.gamecanoplay.fr ──▶ Authelia (identifiant + mot de passe, anti-force brute)
                    └── gamecanoplay.fr  ──▶ forward_auth Authelia ──┬─▶ /docs/* : portail des docs (fichiers statiques, groupe « equipe »)
                                                                      └─▶ le reste : jeu-bleu | jeu-vert (port 8765, réseau interne)
```

## Déploiement continu

1. Push sur `main` dans `matrix-game` → workflow **Checks** (ruff + pytest).
2. S'il est vert → workflow **Déploiement** : `docker build`, puis `docker save | ssh deploiement@VPS <tag>`.
   Pas de registre d'images, aucun identifiant de registre sur le serveur.
3. Sur le VPS, la clé SSH ne peut lancer **que** `deployer.sh` (forced command), qui :
   - refuse tout tag qui n'est pas 12 caractères hexadécimaux ;
   - **n'interrompt jamais une partie** : si `/sante` annonce des parties en cours, la version est
     mise en attente ; un minuteur systemd réessaie tous les quarts d'heure ; au-delà de 24 h
     (partie abandonnée), la bascule a lieu et les parties se reprennent depuis « Parties sauvegardées »
     (une partie n'est sauvegardée qu'après son premier tour) ;
   - démarre la nouvelle couleur, attend qu'elle soit saine, bascule Caddy, arrête l'ancienne ;
   - si la nouvelle version n'est pas saine, **l'ancienne reste en ligne**.

## Portail des docs — `https://gamecanoplay.fr/docs/`

- Construit par `scripts/construire_docs.py` (dépôt matrix-game) à chaque push sur `main` qui touche `docs/` :
  chaque dossier avec `deck.json` + `index.html` devient une présentation, chaque `.md` une page HTML.
- Envoyé par le workflow **Docs** avec la même clé SSH, en mode `docs` : `deployer.sh` extrait l'archive dans
  `etat/docs/versions/<date>`, bascule le lien `etat/docs/courant` d'un coup et garde 3 versions.
  Archive illisible, de plus de 50 Mo ou sans `index.html` : refusée, la version en ligne reste.
- Accès : groupe **equipe** seulement (règle Authelia) ; un compte « joueurs » reçoit 403 sur `/docs`.

## Mise en place (une fois)

| # | Qui | Action |
|---|---|---|
| 1 | registrar | DNS de `gamecanoplay.fr` : `@`, `www` et `auth` → A `57.129.164.101` (fait), AAAA `2001:41d0:801:2000::7eb8` (facultatif) |
| 2 | poste local | `ssh-keygen -t ed25519 -N "" -C deploiement-jeu -f ~/.ssh/deploiement-jeu` |
| 3 | VPS (root) | copier ce dossier, puis `sudo ACME_EMAIL=… ADMIN_IDENT=… bash installer_vps.sh "$(cat ~/.ssh/deploiement-jeu.pub)"` |
| 4 | VPS | `sudo nano /opt/jeu/etat/jeu.env` → `ANTHROPIC_API_KEY=…` (fixer une limite de dépense dans la console Anthropic) |
| 5 | **propriétaire de matrix-game** | secrets Actions : `VPS_HOTE`, `VPS_CLE_SSH` (contenu de `~/.ssh/deploiement-jeu`), `VPS_EMPREINTE_SSH` (`ssh-keyscan -t ed25519 57.129.164.101`) |
| 6 | matrix-game | relancer le workflow **Déploiement** (ou pousser sur `main`) |

## Exploitation

| Besoin | Commande (sur le VPS) |
|---|---|
| Ajouter / réinitialiser un joueur | `sudo /opt/jeu/ajouter_joueur.sh <identifiant> "Nom"` (préfixer `GROUPES=joueurs,equipe` pour les docs) |
| Donner / retirer l'accès aux docs | `sudo /opt/jeu/groupes_joueur.sh <identifiant> joueurs,equipe` (ou `joueurs`) |
| Retirer un joueur | supprimer son bloc dans `/opt/jeu/etat/utilisateurs.yml` (pris en compte à chaud) |
| Version en ligne / en attente | `cat /opt/jeu/etat/version_en_ligne /opt/jeu/etat/version_en_attente` |
| Journaux | `docker logs jeu-bleu` (ou `jeu-vert`), `journalctl -u jeu-deploiement-en-attente` |
| Exiger un code TOTP | `policy: two_factor` dans `authelia/configuration.yml`, puis `docker compose restart authelia` |

## Tester en local

`PORTAIL=<portail construit> infra/jeu/test_local.sh …` rejoue toute la chaîne avec Docker (certificats locaux) : 31 vérifications —
portail des docs (accès equipe / refus joueurs, versions, archive invalide),
connexion, refus du mauvais mot de passe, `/sante` invisible depuis Internet, mise en attente pendant
une partie, bascule, version défaillante refusée, tag injecté refusé.
