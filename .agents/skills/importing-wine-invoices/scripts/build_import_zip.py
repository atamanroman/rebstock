#!/usr/bin/env python3
"""Build a rebstock import zip from resolved invoice lines.

    build_import_zip.py items.json out.zip

items.json is a list of objects. Matched lines carry a Vivino wine id and the
year; everything else is fetched from Vivino:

    {"wine_id": 2701446, "year": "2022", "bottles": 2}

Lines with no Vivino match spell the wine out instead, and import without a link:

    {"winery": "Ziari", "name": "Petnat Kisi Sauvignon Blanc", "year": "2025",
     "wine_type": "Sparkling", "country": "Georgia", "bottles": 1}

The zip carries cellar.csv plus a header-only full_wine_list.csv, which
import_from_zip requires to exist.
"""

import csv
import json
import sys
import time
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from vivino import wine as fetch_wine  # noqa: E402

CELLAR_HEADER = [
    "Winery", "Wine name", "Vintage", "Region", "Country", "Regional wine style",
    "Average rating", "Wine ratings count", "Wine type", "Link to wine", "User cellar count",
]
WINE_LIST_HEADER = (
    "Winery,Wine name,Vintage,Region,Country,Regional wine style,Average rating,"
    "Scan date,Scan/Review Location,Your rating,Your review,Personal Note,Wine type,"
    "Drinking Window,Link to wine,Label image"
)


def row_from_vivino(item):
    d = fetch_wine(item["wine_id"])
    year = str(item["year"])
    vintage_id = d["vintages"].get(year)
    if vintage_id is None:
        raise SystemExit(
            f"wine {item['wine_id']} ({d['winery']} — {d['name']}) has no {year} vintage; "
            f"available: {sorted(d['vintages'])}"
        )
    # A 0 rating means Vivino has none. Blank it, or rebstock stores a real 0.0.
    rating = d["rating"] or ""
    return [
        d["winery"], d["name"], year, d["region"], d["country"] or "", "",
        rating, d["ratings_count"] if rating else "", d["wine_type"],
        # Vintage id, not wine id: extract_vivino_id only parses /wines/.
        f"https://www.vivino.com/wines/{vintage_id}", item["bottles"],
    ]


def row_manual(item):
    return [
        item["winery"], item["name"], item.get("year", ""), item.get("region", ""),
        item.get("country", ""), "", "", "", item.get("wine_type", "Red Wine"),
        "", item["bottles"],
    ]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    items = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])

    rows = []
    for item in items:
        rows.append(row_from_vivino(item) if "wine_id" in item else row_manual(item))
        time.sleep(0.2)

    cellar = out.parent / "cellar.csv"
    wine_list = out.parent / "full_wine_list.csv"
    with cellar.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(CELLAR_HEADER)
        writer.writerows(rows)
    wine_list.write_text(WINE_LIST_HEADER + "\n", encoding="utf-8")

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(wine_list, "full_wine_list.csv")
        z.write(cellar, "cellar.csv")

    bottles = sum(int(r[-1]) for r in rows)
    print(f"{out}: {len(rows)} wines, {bottles} bottles")
    for r in rows:
        print(f"  {r[0]} — {r[1]} {r[2]} ({r[8]}) x{r[10]}{'' if r[9] else '  [no Vivino link]'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
