# P2 — 14.11.2026 — Source ShipMemory market observations and N128 XP command Apply

**Authority:** single N158 TickRunner / N39 World / N9 Ledger / N104 ContractBoard / N38 SaveState. One integration PR #249. **SOURCE_WIRED / CODE_UNVERIFIED**: GitHub static cross-check ONLY, no Godot parse/runtime, no Actions, no Windows/playtest.

## Frozen Rust source
- `native/crates/sim_core/src/agents/ship/mod.rs::tick_ships`: N140 fired gate → real N14 transit → `observe_prices` → N149 original crew upkeep → N84 decisions and N146 Apply.
- `observe_prices` reads current ORIGINAL `MarketPricing` only when physical `ShipPosition.location_name` exists, with N51 fitted Comms T1 same body / T2 whole system / T3 neighboring system via actual `gate_pairs`. Samples are `PriceMemory {price, tick}` overwritten at each observation, not a global market copy.
- `native/crates/sim_core/src/agents/ship/components.rs::ShipMemory`: price knowledge, visited, recent systems, route performance, contract rejections; first birth empty. `advance_transits` inserts real destination into `visited` ONLY after arrival.
- `native/crates/sim_server/src/engine/apply.rs::SimCommand::GrantCrewXp`: directly invokes `ShipCrewSkills::grant(skill, amount)` u8, saturating to 100; unknown skill is no-op.

## Real source wiring committed
1. New `godot/scripts/sim/phase2/unified_native_ship_price_observation.gd`: source comms-tier and visibility policy, actual reciprocal physical GateLink pairs, exact N140-fired ship records and real MarketPricing, immutable candidate with `price_knowledge[location][commodity]={price,tick}`. Does NOT use rendered positions, all route edges, fake prices or parallel market.
2. `native_location_resolver.gd::body_for_location` exposes existing frozen planet location registry; no invented body topology. `native_fleet_bootstrap.gd` seeds empty source ShipMemory, NOT full-galaxy knowledge.
3. `n39_native_world_production.gd::apply_native_ship_price_observation` accepts only real per-ship memory changes and validates N39 Schema and every unchanged N9 balance. N158 calls this after actual N14 and before N149/N84, with same N140 fired map.
4. `unified_ship_phase.gd` updates `ShipMemory.visited` on real N14 arrival only, not on route planning or teleport. Rust `recent_systems` is updated on actual GATE JUMP only (no fake on ordinary directed transit).
5. N39 Schema and N158 N38 normalization preserve source sampled prices and **integer** observation ticks; old P2 saves lacking ShipMemory reconstruct empty literal source defaults on first authentic observation.
6. N146/N84 now permit authentic `GrantCrewXp` typed commands, and N158 dispatches them through N39 `apply_native_n128_crew_xp` to the real ShipCrewSkills (saturating cap 100) with a persisted source-grant receipt. No duplicate application, fake wage/ship credits or second progression system. Unknown skill no-op matching Rust. N38 normalization and Schema validate source receipts; retired actor history stays archived.

## Remaining REAL integration / verification gaps
- **N83's autonomous free trade loop is not implemented end-to-end in P2.** Source `native_trade_route_policy.gd` exists and memory is now real, but N84 standalone `SellAll`/unassigned `Buy` still lacks fully paid N97/N9 transactional execution. Do not claim autonomous market arbitrage or silently execute offers; build a single ship economic request/Apply bridge against the original Rust `actions.rs` and `engine/transactions.rs` next.
- Current N84 source action paths did not emit `GrantCrewXp` in the reviewed P2 port, and reviewed original `actions.rs`/`behavior.rs` did not contain a `GrantCrewXp` producer. N128 typed command consumer is now wired but cannot assert in-game skill gains until the authentic producer is found/ported. Do NOT award experience per idle tick.
- Rust `ShipEconomy.efficiency` is updated from crew in `tick_crew`; direct read sites reviewed in source ship action/behavior/transactions did not prove an extra trade modifier. The current N149 stores it faithfully. Do NOT invent a discount/bonus before identifying an actual Rust consumer.
- Actual gate jumps / `recent_systems` source update, N83 buy/sell contracts, exact f32 parity and saved-flight replay remain to be completed/tested in the full post-integration test phase.
- Static GitHub readback of eight touched GDScripts checked brackets/quote pairing, matching file indentation, zero NUL, newline, required preloads and wiring; **NO Godot parser / run / Windows build / Actions**.
