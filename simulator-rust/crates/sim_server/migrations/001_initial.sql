-- World layer

CREATE TABLE IF NOT EXISTS star_systems (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    universe_offset_x REAL NOT NULL DEFAULT 0.0,
    universe_offset_y REAL NOT NULL DEFAULT 0.0,
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS celestial_bodies (
    id INTEGER PRIMARY KEY,
    body_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    body_type TEXT NOT NULL,
    orbit_radius REAL NOT NULL,
    orbit_period INTEGER NOT NULL,
    current_angle REAL NOT NULL DEFAULT 0.0,
    resources TEXT NOT NULL DEFAULT '{}',  -- JSON: {commodity_str: richness_f32}
    biome TEXT,
    star_system_id INTEGER NOT NULL REFERENCES star_systems(id) ON DELETE CASCADE,
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_bodies_system ON celestial_bodies(star_system_id);

CREATE TABLE IF NOT EXISTS locations (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    loc_type TEXT NOT NULL,
    celestial_body_id INTEGER NOT NULL REFERENCES celestial_bodies(id) ON DELETE CASCADE,
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_locations_body ON locations(celestial_body_id);

CREATE TABLE IF NOT EXISTS travel_routes (
    id INTEGER PRIMARY KEY,
    from_location TEXT NOT NULL,
    to_location TEXT NOT NULL,
    distance INTEGER NOT NULL,
    UNIQUE(from_location, to_location)
);
CREATE INDEX IF NOT EXISTS idx_routes_from ON travel_routes(from_location);

-- Factions

CREATE TABLE IF NOT EXISTS factions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    faction_type TEXT NOT NULL,
    description TEXT,
    home_system TEXT NOT NULL DEFAULT '',
    treasury INTEGER NOT NULL DEFAULT 0,
    personality TEXT NOT NULL DEFAULT '{}',  -- JSON: Personality
    colors TEXT NOT NULL DEFAULT '{}',       -- JSON: {primary, secondary}
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Facilities

CREATE TABLE IF NOT EXISTS facilities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    facility_type TEXT NOT NULL,
    location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    location_name TEXT NOT NULL DEFAULT '',
    body_id TEXT NOT NULL DEFAULT '',
    faction_id TEXT NOT NULL DEFAULT '',
    docking_capacity INTEGER NOT NULL DEFAULT 5,
    services TEXT NOT NULL DEFAULT '[]',  -- JSON: [service_str]
    condition REAL NOT NULL DEFAULT 1.0,
    reputation INTEGER NOT NULL DEFAULT 50,
    credits INTEGER NOT NULL DEFAULT 10000,
    -- Volatile (typed columns, not a blob)
    reserves TEXT NOT NULL DEFAULT '{}',   -- JSON: {commodity_str: qty_f32}
    docked_ships TEXT NOT NULL DEFAULT '[]', -- JSON: [ship_db_id]
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_facilities_location ON facilities(location_id);
CREATE INDEX IF NOT EXISTS idx_facilities_faction ON facilities(faction_id);

-- Markets

CREATE TABLE IF NOT EXISTS markets (
    id INTEGER PRIMARY KEY,
    facility_id INTEGER NOT NULL UNIQUE REFERENCES facilities(id) ON DELETE CASCADE,
    facility_location TEXT NOT NULL DEFAULT '',  -- denormalized for fast lookup
    price_elasticity REAL NOT NULL DEFAULT 0.02,
    spread REAL NOT NULL DEFAULT 0.10,
    -- Prices, supply, demand kept as JSON maps (13 commodities, always accessed together)
    prices TEXT NOT NULL DEFAULT '{}',       -- JSON: {commodity_str: price_f32}
    supply TEXT NOT NULL DEFAULT '{}',       -- JSON: {commodity_str: qty_f32}
    demand TEXT NOT NULL DEFAULT '{}',       -- JSON: {commodity_str: qty_f32}
    production TEXT NOT NULL DEFAULT '{}',   -- JSON: {commodity_str: qty_f32}
    consumption TEXT NOT NULL DEFAULT '{}',  -- JSON: {commodity_str: qty_f32}
    -- Volatile
    shortage_ticks TEXT NOT NULL DEFAULT '{}',  -- JSON: {commodity_str: ticks_u32}
    price_history TEXT NOT NULL DEFAULT '[]',   -- JSON: [{commodity: price}]
    trade_volume TEXT NOT NULL DEFAULT '{}',    -- JSON: {commodity_str: vol_f32}
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Ships

CREATE TABLE IF NOT EXISTS ships (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    class TEXT NOT NULL DEFAULT 'freighter',
    location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
    location_name TEXT NOT NULL DEFAULT '',  -- denormalized
    system_id TEXT NOT NULL DEFAULT '',
    universe_offset_x REAL NOT NULL DEFAULT 0.0,
    universe_offset_y REAL NOT NULL DEFAULT 0.0,
    position_x REAL NOT NULL DEFAULT 0.0,
    position_y REAL NOT NULL DEFAULT 0.0,
    -- Typed stats (no blob)
    cargo TEXT NOT NULL DEFAULT '{}',            -- JSON: {commodity_str: qty_u32}
    cargo_capacity INTEGER NOT NULL DEFAULT 500,
    fuel REAL NOT NULL DEFAULT 100.0,
    fuel_capacity REAL NOT NULL DEFAULT 100.0,
    fuel_consumption_rate REAL NOT NULL DEFAULT 0.05,
    speed_modifier REAL NOT NULL DEFAULT 1.0,
    credits INTEGER NOT NULL DEFAULT 5000,
    efficiency REAL NOT NULL DEFAULT 1.0,
    faction_id TEXT NOT NULL DEFAULT '',
    faction_reputation TEXT NOT NULL DEFAULT '{}',  -- JSON: {faction_id: rep_u8}
    personality TEXT NOT NULL DEFAULT '{}',          -- JSON: Personality
    -- Volatile (expanded, not a blob)
    docked_at INTEGER,                    -- facility db_id if docked, NULL if not
    transit_from TEXT,                    -- location name or NULL
    transit_to TEXT,                      -- location name or NULL
    transit_departure_tick INTEGER,
    transit_arrival_tick INTEGER,
    current_goal TEXT NOT NULL DEFAULT 'idle',
    active_contract_id TEXT,
    broke_strikes INTEGER NOT NULL DEFAULT 0,
    hoard_strikes INTEGER NOT NULL DEFAULT 0,
    idle_ticks INTEGER NOT NULL DEFAULT 0,
    price_knowledge TEXT NOT NULL DEFAULT '{}',   -- JSON: {loc: {commodity: {price, tick}}}
    visited TEXT NOT NULL DEFAULT '[]',           -- JSON: [location_name]
    cargo_age TEXT NOT NULL DEFAULT '{}',         -- JSON: {commodity_str: tick_u64}
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_ships_location ON ships(location_id);
CREATE INDEX IF NOT EXISTS idx_ships_faction ON ships(faction_id);

-- Crew members

CREATE TABLE IF NOT EXISTS crew_members (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    ship_id INTEGER REFERENCES ships(id) ON DELETE SET NULL,
    facility_id INTEGER REFERENCES facilities(id) ON DELETE SET NULL,
    hunger INTEGER NOT NULL DEFAULT 0,
    fatigue INTEGER NOT NULL DEFAULT 0,
    morale INTEGER NOT NULL DEFAULT 70,
    health INTEGER NOT NULL DEFAULT 100,
    skills TEXT NOT NULL DEFAULT '{}',   -- JSON: {skill_name: level}
    traits TEXT NOT NULL DEFAULT '[]',   -- JSON: [trait_str]
    personality TEXT NOT NULL DEFAULT '{}',
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_crew_ship ON crew_members(ship_id);
CREATE INDEX IF NOT EXISTS idx_crew_facility ON crew_members(facility_id);

-- Populations

CREATE TABLE IF NOT EXISTS populations (
    id INTEGER PRIMARY KEY,
    label TEXT NOT NULL UNIQUE,
    demographic TEXT NOT NULL,
    facility_id INTEGER NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    facility_location TEXT NOT NULL DEFAULT '',
    faction_id TEXT NOT NULL DEFAULT '',
    population_count INTEGER NOT NULL DEFAULT 0,
    overall_sentiment INTEGER NOT NULL DEFAULT 50,
    unrest INTEGER NOT NULL DEFAULT 0,
    total_wealth INTEGER NOT NULL DEFAULT 0,
    food_satisfaction INTEGER NOT NULL DEFAULT 50,
    -- Consumption/production (typed)
    consumption TEXT NOT NULL DEFAULT '{}',     -- JSON: {commodity_str: qty_f32}
    production_commodity TEXT,
    production_amount REAL NOT NULL DEFAULT 0.0,
    employed_fraction REAL NOT NULL DEFAULT 0.85,
    spending_rate REAL NOT NULL DEFAULT 0.02,
    growth_rate REAL NOT NULL DEFAULT 0.001,
    -- Volatile
    migration_pressure REAL NOT NULL DEFAULT 0.0,
    safety_satisfaction INTEGER NOT NULL DEFAULT 50,
    entertainment_satisfaction INTEGER NOT NULL DEFAULT 50,
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_populations_facility ON populations(facility_id);

-- Economy: contracts

CREATE TABLE IF NOT EXISTS contracts (
    id TEXT PRIMARY KEY,  -- UUID string
    contract_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'posted',
    requestor_type TEXT NOT NULL,
    requestor_id TEXT NOT NULL,
    fulfiller_type TEXT,
    fulfiller_id TEXT,
    commodity TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    quantity_remaining INTEGER NOT NULL,
    source_location TEXT NOT NULL,
    destination_location TEXT NOT NULL,
    payment INTEGER NOT NULL,
    escrow_amount INTEGER NOT NULL DEFAULT 0,
    urgency REAL NOT NULL DEFAULT 0.5,
    escalation_rate REAL NOT NULL DEFAULT 0.01,
    faction_id TEXT,
    min_reputation INTEGER NOT NULL DEFAULT 0,
    faction_bonus REAL NOT NULL DEFAULT 0.0,
    posted_at_tick INTEGER NOT NULL DEFAULT 0,
    accepted_at_tick INTEGER,
    picked_up_at_tick INTEGER,
    delivered_at_tick INTEGER,
    expires_at_tick INTEGER,
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON contracts(status);
CREATE INDEX IF NOT EXISTS idx_contracts_destination ON contracts(destination_location);

-- Economy: trades (append-only log)

CREATE TABLE IF NOT EXISTS trades (
    id INTEGER PRIMARY KEY,
    market_id INTEGER NOT NULL REFERENCES markets(id) ON DELETE CASCADE,
    buyer_type TEXT NOT NULL,
    buyer_id INTEGER NOT NULL,
    seller_type TEXT NOT NULL,
    seller_id INTEGER NOT NULL,
    commodity TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    price REAL NOT NULL,
    tick INTEGER NOT NULL,
    executed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_trades_market ON trades(market_id);
CREATE INDEX IF NOT EXISTS idx_trades_tick ON trades(tick);

-- Simulation state (key-value store for tick counter etc.)

CREATE TABLE IF NOT EXISTS simulation_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT '{}',
    inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
