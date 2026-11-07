#!/usr/bin/env python3
"""Génère les pages HTML statiques du site Canoplay.

Une seule source pour l'en-tête, le pied de page et les métadonnées : on modifie ici,
on relance `python3 outils/generer_pages.py`, on commite le HTML produit.
Vercel sert les fichiers tels quels (aucun build côté hébergeur).

Les adresses reprennent celles de Shopify (/collections/all, /products/…, /blogs/infos/…)
pour conserver le référencement acquis.
"""
from __future__ import annotations

import html
import json
import re
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SITE = "https://canoplay.fr"
NOM = "Canoplay"
CONTACT_EMAIL = "adrien.roques@canoplay.fr"
POLITIQUE = "https://m7977n-dm.myshopify.com/policies/privacy-policy"  # en attendant sa reprise

NAV = [
    ("/", "Accueil"),
    ("/collections/all", "Nos Wargames"),
    ("/pages/contact", "Contact"),
    ("/blogs/infos", "Blog"),
    ("/jouer", "Jouer"),
]
JEU_URL = "https://jeu.canoplay.fr/"

# --- Contenu ---------------------------------------------------------------

WARGAMES = [
    {
        "slug": "spaceops",
        "titre": "SpaceOps",
        "accroche": "Jeu de cartes stratégique : construisez votre flotte spatiale et emportez la guerre sur Terre.",
        "description": (
            "<p><strong>SpaceOps</strong> est un jeu de cartes stratégique qui plonge les joueurs dans "
            "l'univers de l’action dans l’Espace. Chaque carte représente une nation spatiale engagée dans "
            "une guerre de haute intensité. Le but du jeu est de construire la meilleure flotte spatiale, de "
            "neutraliser les capacités de support aux opérations ennemies pour emporter la guerre sur Terre.</p>"
        ),
        "images": [
            {"base": "spaceops-dos", "l": 1024, "h": 1500,
             "alt": "Dos des cartes SpaceOps : logo Canoplay Space Force sur fond spatial"},
            {"base": "spaceops-carte", "l": 1024, "h": 1536,
             "alt": "Cartes SpaceOps étalées en éventail, carte « Tour de jeu » et boîte « Stratégie Spatiale de Défense »"},
        ],
    },
]

ARTICLES = [
    {
        "slug": "lusage-du-wargaming-par-les-differentes-armees-pendant-la-seconde-guerre-mondiale",
        "titre": "L'Usage du Wargaming par les Différentes Armées Pendant la Seconde Guerre Mondiale",
        "date": "2025-02-02T16:20:15+01:00",
        "date_txt": "2 février 2025",
        "resume": ("Le wargaming n'est pas seulement un passe-temps pour les passionnés d'histoire et de "
                   "stratégie militaire. Dès ses débuts, il a été utilisé comme un outil de planification et de "
                   "formation par les armées du monde entier."),
        "image": {"base": "blog-wargaming-ww2", "l": 1024, "h": 684,
                  "alt": "Deux militaires penchés sur un wargame de plateau, figurines et cartes sur une carte hexagonale"},
    },
]

# --- Gabarits --------------------------------------------------------------

def esc(t: str) -> str:
    return html.escape(t, quote=True)


def srcset(base: str, tailles: list[int]) -> str:
    return ", ".join(f"/assets/img/{base}-{t}.webp {t}w" for t in tailles)


def tete(titre: str, description: str, chemin: str, image: str, jsonld: list[dict],
         precharge: str = "", type_og: str = "website") -> str:
    url = SITE + chemin
    ld = "\n".join(
        f'<script type="application/ld+json">{json.dumps(d, ensure_ascii=False)}</script>' for d in jsonld
    )
    return f"""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(titre)}</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="{url}">
<meta name="theme-color" content="#f3f3f3">
<meta property="og:type" content="{type_og}">
<meta property="og:site_name" content="{NOM}">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{esc(titre)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:image" content="{SITE}{image}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/assets/img/logo-240.webp" type="image/webp">
<link rel="preload" href="/assets/fonts/assistant-latin.woff2" as="font" type="font/woff2" crossorigin>
{precharge}<link rel="stylesheet" href="/assets/css/site.css">
{ld}
</head>
<body>
<a class="skip" href="#contenu">Aller au contenu</a>
<div class="announce" role="region" aria-label="Annonce">Bienvenue chez Canoplay</div>
"""


def actif(lien: str, section: str) -> str:
    return ' aria-current="page"' if lien == section else ""


def entete(section: str) -> str:
    items = "\n".join(f'      <li><a href="{l}"{actif(l, section)}>{t}</a></li>' for l, t in NAV)
    return f"""<header class="site-header">
<div class="page-width header">
  <details class="menu">
    <summary aria-label="Ouvrir le menu"><svg width="20" height="16" viewBox="0 0 20 16" aria-hidden="true"><path d="M0 1h20M0 8h20M0 15h20" stroke="currentColor" stroke-width="1.5"/></svg></summary>
    <ul>
{items}
    </ul>
  </details>
  <a class="header__logo" href="/"><img src="/assets/img/logo-240.webp" width="90" height="90" alt="Canoplay — accueil"></a>
  <nav class="nav" aria-label="Navigation principale">
    <ul>
{items}
    </ul>
  </nav>
</div>
</header>
"""


PIED = f"""<footer class="footer">
  <div class="page-width">
    <p>© 2026, {NOM}</p>
    <ul>
      <li><a href="/pages/contact">Coordonnées</a></li>
      <li><a href="{POLITIQUE}">Politique de confidentialité</a></li>
    </ul>
  </div>
</footer>
</body>
</html>
"""


def fil(etapes: list[tuple[str, str]]) -> tuple[str, dict]:
    """Fil d'Ariane visible + données structurées BreadcrumbList."""
    lis = []
    for i, (lien, nom) in enumerate(etapes):
        dernier = i == len(etapes) - 1
        lis.append(f'<li><span aria-current="page">{esc(nom)}</span></li>' if dernier
                   else f'<li><a href="{lien}">{esc(nom)}</a></li>')
    visible = f'<nav class="page-width breadcrumb" aria-label="Fil d\'Ariane"><ol>{"".join(lis)}</ol></nav>\n'
    ld = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "name": nom, "item": SITE + lien}
        for i, (lien, nom) in enumerate(etapes)]}
    return visible, ld


ORGANISATION = {
    "@context": "https://schema.org", "@type": "Organization", "name": NOM, "url": SITE + "/",
    "logo": SITE + "/assets/img/logo-240.webp", "email": CONTACT_EMAIL,
    "address": {"@type": "PostalAddress", "postalCode": "31860", "addressLocality": "Pins-Justaret",
                "addressCountry": "FR"},
    "founder": [{"@type": "Person", "name": "Florent Hennart", "jobTitle": "Co-Fondateur"},
                {"@type": "Person", "name": "Adrien Roques", "jobTitle": "Co-Fondateur"}],
}

# --- Pages -----------------------------------------------------------------

def page_accueil() -> str:
    corps = (RACINE / "contenu" / "accueil.html").read_text(encoding="utf-8")
    precharge = ('<link rel="preload" as="image" href="/assets/img/blood-moon-1500.webp" '
                 f'imagesrcset="{srcset("blood-moon", [750, 1500])}" '
                 'imagesizes="(min-width: 750px) 50vw, 100vw" fetchpriority="high">\n')
    return (tete("Canoplay, la nouvelle ère du wargaming",
                 "Canoplay conçoit des wargames basés sur des cartes pour le renforcement d'équipe et "
                 "l'initiation à la guerre spatiale : simples, engageants, ancrés dans des contextes réalistes.",
                 "/", "/assets/img/og-image.png", [ORGANISATION], precharge)
            + entete("/") + corps + PIED)


def page_wargames() -> str:
    tuiles = []
    for i, w in enumerate(WARGAMES):
        im = w["images"][0]
        charge = 'fetchpriority="high"' if i == 0 else 'loading="lazy" decoding="async"'
        tuiles.append(f"""  <li class="tile">
    <div class="tile__img"><img src="/assets/img/{im['base']}-600.webp" srcset="{srcset(im['base'], [600, 1024])}" sizes="(min-width: 750px) 25vw, 50vw" width="{im['l']}" height="{im['h']}" alt="" {charge}></div>
    <h2><a href="/products/{w['slug']}">{esc(w['titre'])}</a></h2>
    <p>{esc(w['accroche'])}</p>
  </li>""")
    visible, ld_fil = fil([("/", "Accueil"), ("/collections/all", "Nos Wargames")])
    ld_liste = {"@context": "https://schema.org", "@type": "ItemList", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "url": f"{SITE}/products/{w['slug']}", "name": w["titre"]}
        for i, w in enumerate(WARGAMES)]}
    corps = f"""<main id="contenu">
{visible}<div class="page-width">
<h1 class="page-title">Nos Wargames</h1>
<ul class="grid">
{chr(10).join(tuiles)}
</ul>
</div>
</main>
"""
    return (tete("Nos Wargames — Canoplay",
                 "Découvrez les wargames Canoplay : des jeux de cartes conçus pour le renforcement d'équipe "
                 "et l'initiation à la guerre spatiale.",
                 "/collections/all", f"/assets/img/{WARGAMES[0]['images'][0]['base']}-1024.webp",
                 [ld_fil, ld_liste]) + entete("/collections/all") + corps + PIED)


def page_wargame(w: dict) -> str:
    figures = []
    for i, im in enumerate(w["images"]):
        premiere = i == 0
        taille = "(min-width: 990px) 60vw, 100vw" if premiere else "(min-width: 990px) 30vw, 50vw"
        charge = 'fetchpriority="high"' if premiere else 'loading="lazy" decoding="async"'
        figures.append(f'  <img class="{"first" if premiere else ""}" src="/assets/img/{im["base"]}-1024.webp" '
                       f'srcset="{srcset(im["base"], [600, 1024])}" sizes="{taille}" width="{im["l"]}" '
                       f'height="{im["h"]}" alt="{esc(im["alt"])}" {charge}>')
    visible, ld_fil = fil([("/", "Accueil"), ("/collections/all", "Nos Wargames"),
                           (f"/products/{w['slug']}", w["titre"])])
    texte = re.sub(r"<[^>]+>", "", w["description"])
    ld_jeu = {"@context": "https://schema.org", "@type": "Game", "name": w["titre"],
              "description": texte, "url": f"{SITE}/products/{w['slug']}",
              "image": [f"{SITE}/assets/img/{im['base']}-1024.webp" for im in w["images"]],
              "genre": "Jeu de cartes stratégique", "publisher": {"@type": "Organization", "name": NOM}}
    precharge = (f'<link rel="preload" as="image" href="/assets/img/{w["images"][0]["base"]}-1024.webp" '
                 f'imagesrcset="{srcset(w["images"][0]["base"], [600, 1024])}" '
                 'imagesizes="(min-width: 990px) 60vw, 100vw" fetchpriority="high">\n')
    corps = f"""<main id="contenu">
{visible}<article class="page-width product">
<div class="product__media">
{chr(10).join(figures)}
</div>
<div class="product__info">
  <h1>{esc(w['titre'])}</h1>
  {w['description']}
  <a class="btn btn--dark" href="/pages/contact">Nous contacter</a>
</div>
</article>
</main>
"""
    return (tete(f"{w['titre']} — Canoplay", texte[:155].rsplit(" ", 1)[0] + "…",
                 f"/products/{w['slug']}", f"/assets/img/{w['images'][0]['base']}-1024.webp",
                 [ld_fil, ld_jeu], precharge, "product") + entete("/collections/all") + corps + PIED)


def page_blog() -> str:
    cartes = []
    for i, a in enumerate(ARTICLES):
        im = a["image"]
        charge = 'fetchpriority="high"' if i == 0 else 'loading="lazy" decoding="async"'
        cartes.append(f"""  <li class="post-card">
    <img src="/assets/img/{im['base']}-1024.webp" srcset="{srcset(im['base'], [720, 1024])}" sizes="(min-width: 1200px) 1100px, 100vw" width="{im['l']}" height="{im['h']}" alt="" {charge}>
    <h2><a href="/blogs/infos/{a['slug']}">{esc(a['titre'])}</a></h2>
    <time class="meta" datetime="{a['date']}">{a['date_txt']}</time>
    <p>{esc(a['resume'])}</p>
  </li>""")
    visible, ld_fil = fil([("/", "Accueil"), ("/blogs/infos", "Blog")])
    corps = f"""<main id="contenu">
{visible}<div class="page-width">
<h1 class="page-title">Infos</h1>
<ul class="posts">
{chr(10).join(cartes)}
</ul>
</div>
</main>
"""
    return (tete("Blog — Canoplay", "Articles Canoplay sur l'histoire et la pratique du wargaming.",
                 "/blogs/infos", f"/assets/img/{ARTICLES[0]['image']['base']}-1024.webp", [ld_fil])
            + entete("/blogs/infos") + corps + PIED)


def page_article(a: dict) -> str:
    dossier = RACINE / "contenu" / "blog"
    chapeau = (dossier / f"{a['slug']}.chapeau.html").read_text(encoding="utf-8")
    texte = (dossier / f"{a['slug']}.html").read_text(encoding="utf-8")
    im = a["image"]
    visible, ld_fil = fil([("/", "Accueil"), ("/blogs/infos", "Blog"), (f"/blogs/infos/{a['slug']}", a["titre"])])
    ld_art = {"@context": "https://schema.org", "@type": "BlogPosting", "headline": a["titre"],
              "datePublished": a["date"], "image": f"{SITE}/assets/img/{im['base']}-1024.webp",
              "author": {"@type": "Organization", "name": NOM, "url": SITE + "/"},
              "publisher": {"@type": "Organization", "name": NOM,
                            "logo": {"@type": "ImageObject", "url": SITE + "/assets/img/logo-240.webp"}},
              "mainEntityOfPage": f"{SITE}/blogs/infos/{a['slug']}", "inLanguage": "fr-FR"}
    precharge = (f'<link rel="preload" as="image" href="/assets/img/{im["base"]}-1024.webp" '
                 f'imagesrcset="{srcset(im["base"], [720, 1024])}" imagesizes="100vw" fetchpriority="high">\n')
    corps = f"""<main id="contenu">
{visible}<article>
<div class="article__cover page-width"><img src="/assets/img/{im['base']}-1024.webp" srcset="{srcset(im['base'], [720, 1024])}" sizes="(min-width: 1200px) 1100px, 100vw" width="{im['l']}" height="{im['h']}" alt="{esc(im['alt'])}" fetchpriority="high"></div>
<div class="article">
<header class="article__header">
  <h1>{esc(a['titre'])}</h1>
  <time class="meta" datetime="{a['date']}">{a['date_txt']}</time>
</header>
<div class="article__lead">
{chapeau}</div>
{texte}<a class="btn btn--dark article__back" href="/blogs/infos">← Retour au blog</a>
</div>
</article>
</main>
"""
    return (tete(f"{a['titre']} — Canoplay", a["resume"][:155].rsplit(" ", 1)[0] + "…",
                 f"/blogs/infos/{a['slug']}", f"/assets/img/{im['base']}-1024.webp",
                 [ld_fil, ld_art], precharge, "article") + entete("/blogs/infos") + corps + PIED)


def page_jouer() -> str:
    visible, ld_fil = fil([("/", "Accueil"), ("/jouer", "Jouer")])
    ld_jeu = {"@context": "https://schema.org", "@type": "WebApplication", "name": "Matrix game Canoplay",
              "url": JEU_URL, "applicationCategory": "GameApplication", "operatingSystem": "Navigateur web",
              "inLanguage": "fr-FR", "publisher": {"@type": "Organization", "name": NOM}}
    corps = f"""<main id="contenu">
{visible}<div class="page-width contact">
<h1 class="page-title">Matrix game</h1>
<p class="lead">Un <em>matrix game</em> est un jeu de simulation de conflit argumenté : chaque joueur
propose une action et la défend par des arguments, l'arbitre en tranche l'issue. Dans le nôtre,
chaque rôle — joueur ou arbitre — peut être tenu par un humain ou par une IA.</p>
<p>Les scénarios couvrent des crises diplomatiques et des wargames prospectifs sur la guerre dans
l'espace, avec un catalogue commun de moyens spatiaux. La partie se joue dans le navigateur.</p>
<p><strong>Accès sur invitation</strong> : un identifiant vous est remis par Canoplay.</p>
<p class="actions"><a class="btn btn--dark" href="{JEU_URL}">Jouer</a>
<a class="lien" href="/pages/contact">Demander un accès</a></p>
</div>
</main>
"""
    return (tete("Jouer au matrix game — Canoplay",
                 "Le matrix game Canoplay : simulation de conflit argumentée où chaque rôle est tenu par un "
                 "humain ou une IA. Accès sur invitation.",
                 "/jouer", "/assets/img/og-image.png", [ld_fil, ld_jeu]) + entete("/jouer") + corps + PIED)


def page_contact() -> str:
    visible, ld_fil = fil([("/", "Accueil"), ("/pages/contact", "Contact")])
    corps = f"""<main id="contenu">
{visible}<div class="page-width contact">
<h1 class="page-title">Contact</h1>
<dl>
  <dt>Nom commercial</dt><dd>{NOM}</dd>
  <dt>E-mail</dt><dd><a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a></dd>
  <dt>Adresse</dt><dd>31860 Pins-Justaret, France</dd>
  <dt>Numéro d’entreprise</dt><dd>J00068251925</dd>
</dl>
<a class="btn btn--dark" href="mailto:{CONTACT_EMAIL}">Écrire un e-mail</a>
</div>
</main>
"""
    return (tete("Contact — Canoplay", "Contacter Canoplay : e-mail et coordonnées.", "/pages/contact",
                 "/assets/img/og-image.png", [ld_fil, ORGANISATION]) + entete("/pages/contact") + corps + PIED)


def sitemap(chemins: list[str]) -> str:
    urls = "\n".join(f"  <url><loc>{SITE}{c}</loc></url>" for c in chemins)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}\n</urlset>\n')


def main() -> None:
    pages = {
        "/": ("index.html", page_accueil()),
        "/collections/all": ("collections/all.html", page_wargames()),
        "/blogs/infos": ("blogs/infos/index.html", page_blog()),
        "/pages/contact": ("pages/contact.html", page_contact()),
        "/jouer": ("jouer.html", page_jouer()),
    }
    for w in WARGAMES:
        pages[f"/products/{w['slug']}"] = (f"products/{w['slug']}.html", page_wargame(w))
    for a in ARTICLES:
        pages[f"/blogs/infos/{a['slug']}"] = (f"blogs/infos/{a['slug']}.html", page_article(a))
    for _, (fichier, contenu) in pages.items():
        cible = RACINE / fichier
        cible.parent.mkdir(parents=True, exist_ok=True)
        cible.write_text(contenu, encoding="utf-8")
        print("écrit", fichier)
    (RACINE / "sitemap.xml").write_text(sitemap(list(pages)), encoding="utf-8")
    print("écrit sitemap.xml")


if __name__ == "__main__":
    main()
