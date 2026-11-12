# N137 — native ship utility considerations (Phase 1)

Status: CODE_UNVERIFIED. Source: frozen `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`, `native/crates/sim_core/src/ai/considerations.rs`.

## Covered original functions
- `fuel_urgency`: `1 - ShipFuel::fraction()`, zero-capacity fraction = 0.
- `trade_opportunity`: all unordered pairs of locations and common commodities; relative margin `(hi-lo)/max(lo,1)`, minimum quote freshness; normalized by 2 and clamped.
- `price_freshness_weight` dependency from `agents/ship/mod.rs`: `2^(-max(current-observed,0)/1500)`, clamped to [0.10,1].
- `cargo_opportunity`, `cargo_to_sell`: original u32 quantity sum, saturating free capacity, capacity denominator >=1.
- `financial_pressure`: exact credit thresholds <=0, <500, <2000, <10000.
- `exploration_desire`: 0.3 fallback when no visited or no known prices; unique visited locations; ratio of known unvisited locations.
- `docked_at_facility`: Some/None to 1/0 safety.
- `snapshot_all`: optional convenience wrapper for existing N85 utility scoring, does not change native formulas.

## Contract and limits
All input is read-only Dictionary snapshot. Return shape `{"value": float, "axis": "profit|safety|exploration"}`, matching N85 consideration contract concept. Source Rust `f32` math maps to Godot floating-point; bit-exact f32 parity is NOT claimed. Cargo quantities must already be valid nonnegative u32 as in Rust `ShipCargo`; invalid input validation belongs to native cargo admission. No cargo, money, contracts, ships or Nodes are created. Price quote timestamps are native ticks, not wall-clock time. The source contains only seven consideration functions; no extra synthetic aggression/morale factors were invented.

## Phase 2 handoff
Bind authoritative ship snapshots and tick to these pure functions, and map the returned consideration names to the actual action factors used by the ship AI. Do not interpret scores as execution or payment. Source review + GitHub readback + simple delimiter check only; no Godot runtime, no full regression and no integration into P1 checkpoint.
