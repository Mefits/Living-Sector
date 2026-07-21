-- Phase 19g: retirement ledger.
--
-- Historical record of every ship that leaves the sim. Retained
-- after the ships row is deleted so the player can scroll back
-- through "what happened to Dusk Panther?" — ship got broke?
-- decommissioned by admin? hit a hoard strike?
--
-- Every row is append-only. The application layer never updates
-- or deletes these rows; that's what the active ships table is for.

CREATE TABLE IF NOT EXISTS retired_ships (
    id INTEGER PRIMARY KEY,
    agent_id TEXT NOT NULL,      -- original ship_by_id key, e.g. "ship-dusk-panther"
    name TEXT NOT NULL,
    class TEXT NOT NULL,
    faction_id TEXT NOT NULL DEFAULT '',
    final_location TEXT NOT NULL DEFAULT '',
    final_credits INTEGER NOT NULL DEFAULT 0,
    final_crew_morale INTEGER NOT NULL DEFAULT 0,
    final_fuel_pct INTEGER NOT NULL DEFAULT 0,
    broke_strikes INTEGER NOT NULL DEFAULT 0,
    hoard_strikes INTEGER NOT NULL DEFAULT 0,
    retired_at_tick INTEGER NOT NULL DEFAULT 0,
    reason TEXT NOT NULL DEFAULT 'unknown',
    retired_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_retired_ships_tick ON retired_ships(retired_at_tick);
CREATE INDEX IF NOT EXISTS idx_retired_ships_agent ON retired_ships(agent_id);
