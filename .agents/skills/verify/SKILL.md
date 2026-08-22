---
name: verify
description: Run rebstock and drive it over HTTP to observe a change working end to end
---

# Verifying rebstock

Rebstock is a wisp server, so the surface is a socket: launch it on a scratch port with a scratch database and drive it with `curl`.

## Launch

Write a config anywhere outside the repo — `--config` takes any path, and a missing file silently falls back to defaults, so check the boot log to confirm yours was read.

```json
{
  "host": "127.0.0.1",
  "port": 3999,
  "database_uri": "file:/tmp/scratch/verify.db",
  "image_dir": "/tmp/scratch/images",
  "secret_key_base": "verify-secret-key-base-0123456789",
  "auth": { "single": { "user": "test" } }
}
```

The image directory must already exist.
Run the server in the background and wait for the port instead of sleeping:

```
gleam run -- --config /tmp/scratch/verify-config.json > /tmp/scratch/server.log 2>&1
```

```
until curl -s -o /dev/null http://127.0.0.1:3999/; do sleep 1; done
```

The log's `-> Applied N migrations` line tells you the migration count the fresh database got.
Kill with `pkill -f verify-config.json` when done; the background command then reports exit 144, which is the kill, not a crash.

## Driving it

`auth.Single` makes every request that user, so no login step exists.
CSRF rejects a POST only when `Origin` or `Sec-Fetch-Site` contradicts the host, and curl sends neither — plain `curl -X POST -F` works.

Forms post to a different path than the one that renders them: the new-wine form is at `/wines/new` but posts to `/wines`. Read the `action` before guessing.

A short path to a cellar with bottles in it:

```
curl -s -X POST http://127.0.0.1:3999/wines -F "winery=Dakishvili" -F "name=Kisi Amber Dry" -F "vintage=2023" -F "country=Georgia" -F "wine_type=white"
```

```
curl -s http://127.0.0.1:3999/wines | grep -o '/wines/[A-Z0-9]*/[a-z-]*'
```

```
curl -s -X POST "http://127.0.0.1:3999/wines/<id>/<slug>/cellar/new" -F "vintage=2023" -F "quantity=2" -F "price=18.75" -F "date=2026-08-01"
```

Entry ids for edit, drink and delete come out of the wine page: `grep -o '/cellar/[A-Z0-9]*/drink'`.

Pages worth reading back: `/~test/cellar` (subtitle, table), `/cellar/<entry-id>` (entry card), `/~test/cellar/export.csv` (export), `/` (dashboard).

## Gotchas

- A cellar entry with a vintage needs that vintage on the wine — the `cellar` table has `FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)`. Creating the wine with that vintage covers it; inserting straight through `db` does not.
- HTML comes out as one line, so `tr '>' '>\n'` before grepping, or grep for the specific attribute.
- `just dev` watches files and never exits — never use it to verify.
