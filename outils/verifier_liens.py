#!/usr/bin/env python3
"""Vérifie que chaque ressource et lien interne des pages HTML pointe vers un fichier existant.

Résolution identique à Vercel avec `cleanUrls` : /a/b → a/b, a/b.html ou a/b/index.html.
Sortie non nulle si un seul lien est cassé.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
IGNORES = {".git", "node_modules", ".vercel"}
ATTR = re.compile(r'\b(src|href|srcset|imagesrcset)="([^"]+)"')


def cibles(valeur: str, attribut: str) -> list[str]:
    if attribut in ("srcset", "imagesrcset"):
        return [morceau.strip().split()[0] for morceau in valeur.split(",") if morceau.strip()]
    return [valeur]


def existe(page: Path, ref: str) -> bool:
    chemin = ref.split("#")[0].split("?")[0]
    if not chemin:
        return True
    base = RACINE / chemin.lstrip("/") if chemin.startswith("/") else page.parent / chemin
    return any(p.is_file() for p in (base, base.with_name(base.name + ".html"), base / "index.html"))


def main() -> int:
    casses = 0
    pages = [p for p in RACINE.rglob("*.html") if not IGNORES & set(p.relative_to(RACINE).parts)
             and p.relative_to(RACINE).parts[0] != "contenu"]
    vus = 0
    for page in sorted(pages):
        for attribut, valeur in ATTR.findall(page.read_text(encoding="utf-8")):
            for ref in cibles(valeur, attribut):
                if re.match(r"^(https?:|mailto:|tel:|data:|#|//)", ref):
                    continue
                vus += 1
                if not existe(page, ref):
                    casses += 1
                    print(f"::error file={page.relative_to(RACINE)}::lien cassé : {ref}")
    print(f"{len(pages)} pages, {vus} liens internes vérifiés, {casses} cassé(s)")
    return 1 if casses else 0


if __name__ == "__main__":
    sys.exit(main())
