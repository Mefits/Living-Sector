# 14 Nov 2026 — N148 source adaptive fleet integrated into the single P2 Godot runtime

**Working branch** `integration/godot-phase2-unified-20261113`, one Draft PR #249.
**Status** `SOURCE_WIRED / CODE_UNVERIFIED`. User explicitly deferred all Godot/gameplay tests and rebalance until ALL frozen Rust 0.6.7 source is integrated.

## Actual frozen-source behavior reviewed
- `native/crates/sim_core/src/agents/ship/behavior.rs` near ShipLifecycle 19h/19-tail: one idle increment per fired ship decision, 500×tick_multiplier strike gate, bankruptcy for below 500 credits with empty hold and no contract, reset only after 5000, stagnation above 200000 after >500 idle decisions, max 3 strikes. Bankruptcy has priority; `SimCommand::DecommissionShip` is queued, not directly deleting ECS.
- `native/crates/sim_server/src/engine/apply.rs`: exact source contract payout triggers hoard-strike reset only on real paid delivery.
- `engine/drains.rs::drain_pending_decommissions`: drain after ship phase through `admin_remove_ship`; removal may be blocked when passengers are aboard; patch event reason, emit fleet loss without replacement in Genesis finite hull mode.
- Original P1 N148 ports `n148_native_ship_lifecycle.gd` and `n148_native_ship_retirement_queue.gd` were present in PR #249, but had NO canonical N158 execution or N38 save support.
- Existing preceding P2 N152 administrative deletion `apply_native_admin_removal` is sole authority for N104 cleanup, disappearing physical actor and exact N9 credit write-off.

## Code wired now
1. `native_fleet_bootstrap.gd` stores genuine source `ShipLifecycle.default_lifecycle()` (zero strikes/idle, clean dirty) on every real N46 new-game ship. No free tanks/credits/hulls.
2. New `unified_n148_ship_retirement_phase.gd` invokes the original P1 N148 transition on actual N39 ship credits, cargo quantities, active contract ID and current N84 goal. Uses the existing typed N146 `DecommissionShip` buffer and immutable ship snapshot proposal. No independent clock or income generation. Existing older P2 ships without the new field receive exactly source default on their first real ship tick, not a reinit of physical state.
3. `n39_native_world_production.gd::apply_native_n148_ship_lifecycle` stages and validates source lifecycle changes; only per-ship lifecycle can differ, N9 balances, N104 Board, ship fields and all other world objects remain unchanged. Called at the live ships tick `_last_tick+1`.
4. `n158_production_runtime.gd` evaluates N148 **after N84 plan candidate commit and before its N146 physical commands apply**, consistent with the Rust behavior.rs ordering. It transcribes typed `DecommissionShip` through the original P1 N148 queue, drains after ship transaction Apply, invokes real N39/N152 administrative ship removal at the same authoritative ships-phase tick, and passes the trusted receipt to `on_authoritative_ship_removed`. Source passenger guard is respected: a blocked ship remains physically live and can retry at a later N148 strike cadence.
5. Finite Genesis hulls: sets `auto_replace_retired_ships=false` in source post-commit hook. Emits the source `fleet_loss_unreplaced` event with actual ship ID/faction/reason. Does NOT invent a replacement ship, grant free credits, execute a second ship runner or edit the player's balance design.
6. `apply_autonomous_contract_cargo` resets original N148 hoard strikes **only after real N97/N104 receipt and N9 paid delivery**, inside the same atomic N39 commit. The N39 whitelist permits the single `lifecycle` change on delivery only; broken-ship strikes/idle are preserved.
7. N39 schema validates native lifecycle type and exact bounded integer counters. N158 existing N38 JSON normalization covers `broke_strikes`, `hoard_strikes`, `idle_ticks` and allows a genuine empty fleet after all real ships are lost. Runtime exposes `last_native_ship_retirement()`, ship-phase retirement/blocked stats. The existing N38 world+N9 checkpoint retains ship history and source audit receipts from previous N152 integration.

## Exactly what was NOT verified / outstanding
- Static readback and delimiter/preload/indentation checks only. No Godot parser, headless CI, GitHub Actions, user Windows tests or Rust-vs-Godot differential replay. **Not VERIFIED or complete project parity**.
- Native N140 LOD skip cadence is not independently implemented for all P2 ships; the current N158 ship tick visits each live ship once. Native N148 specifically increments idle only once per fired source decision, so real native LOD must be reconciled for exact parity when integrating/validating N140. No separate fake LOD engine was added.
- Legacy automatic replacement path for non-Genesis worlds is NOT implemented. The current game's finite-hull policy intentionally suppresses free replacement; real shipyard materialization/paid construction remains a separate source integration.
- Actual Rust `DbWrite::DeleteShip/RetireShip` SQLite path is not reproduced; N38 persists true canonical absence, history and N9 receipt. Original Rust has genuine SQL history; parity not asserted.
- P2 frozen gameplay replay/paid freight trace/retirement after 500×mult ticks, save/load before and after third strike, passenger boarding blocker, fleet-zero boot and GUI observer remain final post-integration tests.
- Concurrent second chat owns N126/N147/N142 passenger/colony delivery; no edits to its source modules.
