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

CREATE TABLE lists (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  name TEXT NOT NULL,
  description TEXT,
  slug TEXT NOT NULL,
  list_type TEXT NOT NULL DEFAULT 'custom',
  public INTEGER NOT NULL DEFAULT 0,
  show_bottles INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(username, slug)
);

CREATE TABLE lists_wines (
  list_id TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT NOT NULL DEFAULT '',
  sort_rank INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (list_id, wine_id, vintage)
);

CREATE TRIGGER lists_wines_type_check
BEFORE INSERT ON lists_wines
BEGIN
  SELECT RAISE(ABORT, 'Cannot add wines to virtual lists')
  WHERE (SELECT list_type FROM lists WHERE id = NEW.list_id) IN ('cellar', 'rated');
END;
