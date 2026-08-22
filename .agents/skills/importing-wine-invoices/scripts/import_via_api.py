#!/usr/bin/env python3
"""Create wines and cellar entries in rebstock over HTTP.

    import_via_api.py items.json http://127.0.0.1:3000 admin [--date 2026-07-19]

items.json is a list of objects. A line matched on Vivino carries the wine id,
and rebstock fetches the rest itself — every vintage, per-vintage ratings and
the label image:

    {"wine_id": 12067613, "name": "Tsitska Semi Dry", "winery": "Binekhi",
     "wine_type": "White Wine", "region": "Imereti", "country": "ge",
     "year": "2022", "bottles": 2, "notes": "invoice #37140, EUR 11.30/bottle"}

A line with no Vivino match omits wine_id and is created from its own fields:

    {"winery": "Ziari", "name": "Petnat Kisi Sauvignon Blanc",
     "wine_type": "Sparkling", "country": "ge", "year": "2025", "bottles": 1}

Each cellar POST creates one entry, so re-running duplicates bottles. The wine
POSTs are upserts and safe to repeat. On a partial failure, drop the lines that
already landed before re-running.
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def post(url, fields):
    """Form POST. No Origin header: require_same_origin only compares it when present."""
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        url, data=body, headers={"content-type": "application/x-www-form-urlencoded"}
    )
    # The 303 to the new wine carries the id, so don't follow it. urllib raises
    # on an unfollowed redirect, and the exception is itself the response.
    opener = urllib.request.build_opener(NoRedirect)
    try:
        r = opener.open(req, timeout=60)
    except urllib.error.HTTPError as e:
        r = e
    with r:
        return r.status, r.headers.get("location"), r.headers.get("hx-redirect")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args):
        return None


def create_wine(base, item):
    """Returns the wine id. Vivino-matched wines go through the import endpoint,
    which syncs vintages, ratings and the label image; the rest are created bare."""
    if "wine_id" in item:
        url = f"{base}/wines/import/vivino"
        fields = {
            "name": item["name"],
            "winery": item["winery"],
            "vivino_id": str(item["wine_id"]),
            "wine_type": item.get("wine_type", ""),
            "region": item.get("region", ""),
            "country": item.get("country", ""),
        }
        # name, winery and vivino_id must all be non-empty or the handler
        # redirects back to the form without saying why.
        missing = [k for k in ("name", "winery", "vivino_id") if not fields[k]]
        if missing:
            raise SystemExit(f"{item.get('name')}: missing required field(s) {missing}")
    else:
        # POST /wines, not /wines/new — that path only ever renders the form.
        url = f"{base}/wines"
        fields = {
            "name": item["name"],
            "winery": item["winery"],
            "wine_type": item.get("wine_type", ""),
            "region": item.get("region", ""),
            "country": item.get("country", ""),
            "vintage": item.get("year", ""),
        }

    status, location, _ = post(url, fields)
    if not location or "/wines/" not in location:
        raise SystemExit(f"{item['name']}: unexpected response {status} {location!r}")
    return location.rstrip("/").split("/wines/")[1].split("/")[0]


def add_bottles(base, wine_id, item, default_date):
    fields = {
        "vintage": str(item.get("year", "")),
        "quantity": str(item["bottles"]),
        "date": item.get("date", default_date) or "",
        "notes": item.get("notes", ""),
    }
    status, _, hx = post(f"{base}/wines/{wine_id}/x/cellar/new", fields)
    if status != 200 or not hx:
        raise SystemExit(f"{item['name']}: cellar entry failed, {status}")


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    items = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    base = sys.argv[2].rstrip("/")
    user = sys.argv[3]
    date = ""
    if "--date" in sys.argv:
        date = sys.argv[sys.argv.index("--date") + 1]

    if not base.startswith("http://127.0.0.1") and not base.startswith("http://localhost"):
        print(f"About to write {len(items)} wines to {base} as {user}.")
        print("Remote instance: confirm with the user before running this.", file=sys.stderr)

    bottles = 0
    for item in items:
        wine_id = create_wine(base, item)
        add_bottles(base, wine_id, item, date)
        bottles += int(item["bottles"])
        print(f"  {item['winery']} — {item['name']} {item.get('year','')} x{item['bottles']}  {wine_id}")
    print(f"{len(items)} wines, {bottles} bottles -> {base}/~{user}/cellar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
