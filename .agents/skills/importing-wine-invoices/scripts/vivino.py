#!/usr/bin/env python3
"""Look up Vivino wines and wineries for invoice matching.

    vivino.py wine 2701446        # wine detail + every vintage id
    vivino.py winery 26104        # discover the producer's catalog
    vivino.py winery binekhi      # same, resolving the slug to an id first

Discovery only: get candidates from a web search restricted to vivino.com or
list a producer with `winery`. Verify identities with Rebstock's MCP
`lookup_vivino_wine` tool before linking them during import.
"""

import json
import re
import sys
import urllib.request

MOBILE_UA = "Vivino/8.18.11 (Android; SDK 30)"
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
TYPE_NAMES = {1: "RED", 2: "WHITE", 3: "SPARKLING", 4: "ROSE", 7: "DESSERT", 24: "OTHER"}


def fetch(url, user_agent):
    """urllib, not curl: curl gets a redirect stub from www.vivino.com."""
    req = urllib.request.Request(url, headers={"user-agent": user_agent, "accept": "*/*"})
    return urllib.request.urlopen(req, timeout=40).read().decode("utf-8", "replace")


def summarize(d):
    region = d.get("region") or {}
    country = region.get("country")
    # Prefer locale-stable country codes over localized discovery labels.
    if isinstance(country, dict):
        country = country.get("code") or country.get("seo_name") or country.get("name")
    stats = d.get("statistics") or {}
    return {
        "wine_id": d["id"],
        "winery_id": d.get("winery", {}).get("id"),
        "winery": d.get("winery", {}).get("name"),
        "name": d["name"],
        "type_id": d.get("type_id"),
        "wine_type": TYPE_NAMES.get(d.get("type_id"), "OTHER"),
        "region": region.get("name", ""),
        "country": country,
        "rating": stats.get("ratings_average"),
        "ratings_count": stats.get("ratings_count"),
    }


def wine(wine_id):
    d = json.loads(fetch(f"https://api.vivino.com/wines/{wine_id}", MOBILE_UA))
    out = summarize(d)
    out["vintages"] = {v.get("year"): v.get("id") for v in d.get("vintages", []) if v.get("year")}
    return out


def winery_id_for(slug):
    html = fetch(f"https://www.vivino.com/en/wineries/{slug}", BROWSER_UA)
    match = re.search(r"winery_id=(\d+)", html)
    if not match:
        raise SystemExit(f"no winery id found on the page for {slug!r}")
    return match.group(1)


def winery(ref):
    """Discover a producer's wines; upstream completeness is not guaranteed.

    The www endpoint has historically returned more results than its api
    counterpart. Verify candidate identities through MCP before importing.
    """
    winery_id = ref if ref.isdigit() else winery_id_for(ref)
    d = json.loads(fetch(f"https://www.vivino.com/api/wineries/{winery_id}/wines", BROWSER_UA))
    wines = d["wines"] if isinstance(d, dict) and "wines" in d else d
    return [summarize(w) for w in wines]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    command, arg = sys.argv[1], sys.argv[2]
    if command == "wine":
        print(json.dumps(wine(arg), ensure_ascii=False, indent=2))
    elif command == "winery":
        for w in winery(arg):
            print(json.dumps(w, ensure_ascii=False))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
