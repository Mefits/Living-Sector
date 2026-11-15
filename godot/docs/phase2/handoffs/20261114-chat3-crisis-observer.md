# Living Sector P2 — CHAT3 V2 Rust Bundle(S) observer wiring

Date: 2026-11-14 | shared PR #249 | branch `integration/godot-phase2-unified-20261113`

## Source (frozen Rust Galaxy 0.6.7)

`native/crates/sim_server/src/engine.rs::scan_crisis_events` is called after markets and before apply2/factions. WorldTuning default: market crisis >=200 consecutive shortage ticks, recovery <=50; facility starving <0.3 condition, recovery >0.5. Both are warning hysteresis, not a financial transaction and **not** Director industrial_accident.

## Implemented in this iteration

- `2269c6f`: `unified_native_crisis_events.gd::current_warning_state(world)` validates and reads the **same N39 snapshot**: persisted market `history.crisis_notified`, persisted facility `starving_notified`, and below-threshold facility candidates not yet recorded by canonical N39. Read-only, deterministic sorting, no shadow cache or event queue.
- `68156fd`: `observer_panel.gd` shows concise Rust warning counts in existing compact summary, persisted market flags in Markets and facility states in Stations. Uncommitted facility thresholds explicitly say **signal not yet recorded in N39**. No new panel, timer, World or ledger.
- `5adecff`: deferred regression `p2_native_crisis_observer_projection_check.gd` checks flags, strict hysteresis 0.3/0.5, legacy P2 unflagged markets, source immutability and compact observer summary.

Previous iteration remains: pure proposal `424f890`, live N150 market-history `ce29f2d`, deferred thresholds test `b6c7dde`, handoff `20261114-chat3-native-crisis-events.md`.

## Exact state and blockers

**SOURCE_WIRED / CODE_UNVERIFIED.** The live N150 Market proposal sets persisted crisis flags via the one N39 `apply_market_phase`. The Observer now reads *those flags* from the canonical snapshot. It does not claim a queued event or replay one. `N158` currently does not dispatch `MarketPhase.crisis_events` into the single scheduled/GUI event path. Facilities below threshold without a persisted source flag are merely read-only candidates, **not emitted Rust events**.

No modifications to N39, N158, Schema, SaveState, ledger or contracts due to **chat1 active lease** `20261114-chat1-native-free-trade-apply.json`. Chat2 continues separate colony work. Actions and Godot were not run by request. Static source re-fetch + delimiter counts, line endings and NUL validation passed; not equivalent to GDScript compiler/runtime validation.

## NEXT on «Продолжай»

1. Re-fetch PR #249 HEAD and active claims. When chat1's N39/N158 lease is RELEASED, integrate pure `propose_facility_warnings` at **crisis** phase after N150 markets: same N39 World staged flag + schema validation + exactly-once event handoff. New N38 snapshots persist `starving_notified` in canonical facilities. Old saves remain compatible; do not synthesize already-fired events.
2. Dispatch N150 market transition warnings and N156 facility transition warnings **via one existing runtime event path** without creating another EventQueue. Ensure `market_crisis`, `market_recovered`, `facility_starving`, `facility_recovered` are seen once per crossing and never as commodity sales, repairs or events on load.
3. During final joint testing, validate `markets→crisis→apply2→factions`, save/load and actual Godot static/runtime correctness with both other chats. No intermediate Actions.

Do not activate `strategy/director.rs::environmental_events` industrial damage based solely on presence of its source file.
