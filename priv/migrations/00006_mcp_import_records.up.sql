CREATE TABLE mcp_import_records (
  username TEXT NOT NULL REFERENCES users(username),
  source TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('wines', 'cellar', 'ratings', 'wishlist')),
  source_ref TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  destination_id TEXT NOT NULL,
  wine_id TEXT NOT NULL REFERENCES wines(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (username, source, kind, source_ref)
);
