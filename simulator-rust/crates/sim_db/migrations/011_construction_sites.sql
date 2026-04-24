-- Phase 19c-d: construction-site persistence.
--
-- Sites survive restarts as-is (progress, location, commodity, faction
-- sponsor). On boot the spawner loads them back into the ECS exactly
-- where they were; once a delivery pushes progress to 1.0 the row is
-- deleted and a materialised facility row is inserted in its place.
CREATE TABLE IF NOT EXISTS construction_sites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    facility_type TEXT NOT NULL,
    faction_id TEXT NOT NULL,
    body_id TEXT NOT NULL,
    location_name TEXT NOT NULL,
    commodity TEXT NOT NULL,
    progress_delivered INTEGER NOT NULL DEFAULT 0,
    progress_required INTEGER NOT NULL,
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    spawned_at_tick INTEGER NOT NULL,
    completed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_sites_location ON construction_sites(location_name);
