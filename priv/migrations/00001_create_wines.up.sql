CREATE TABLE users (
  username TEXT PRIMARY KEY
);

CREATE TABLE wineries (
  id TEXT PRIMARY KEY,
  created_by TEXT NOT NULL REFERENCES users(username),
  name TEXT NOT NULL,
  country TEXT,
  vivino_id TEXT,
  UNIQUE(created_by, name)
);

CREATE TABLE wines (
  id TEXT PRIMARY KEY,
  created_by TEXT NOT NULL REFERENCES users(username),
  winery_id TEXT NOT NULL REFERENCES wineries(id),
  name TEXT NOT NULL,
  region TEXT,
  country TEXT,
  style TEXT,
  personal_note TEXT,
  wine_type TEXT NOT NULL,
  vivino_id TEXT,
  UNIQUE(created_by, winery_id, name)
);

CREATE TABLE wines_vintages (
  wine_id TEXT NOT NULL REFERENCES wines(id),
  year TEXT NOT NULL,
  PRIMARY KEY (wine_id, year)
);

CREATE TABLE wishlist (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(username, wine_id, vintage),
  FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)
);

CREATE TABLE cellar (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT,
  quantity INTEGER NOT NULL,
  notes TEXT,
  date TEXT,
  parent_id TEXT REFERENCES cellar(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)
);

CREATE TABLE ratings (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT,
  rating REAL,
  tasting_notes TEXT,
  rated_at TEXT,
  source TEXT NOT NULL DEFAULT 'user',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)
);
