# Chat №1 — follow-up Rust N21 Dock patience, manual paid path and empty-FIFO performance

**Date:** 2026-11-14  
**Repository:** `Mefits/Living-Sector`; branch `integration/godot-phase2-unified-20261113`; one draft PR #249.  
**Status:** **SOURCE_WIRED / CODE_UNVERIFIED / RUNTIME_UNVERIFIED**. No headless Godot, parser, F5, CI, Windows export or scenario tests run.

## Source comparison and work committed

**Original frozen Rust:** `native/crates/sim_core/src/agents/ship/actions.rs` ShipAction::Dock / DockAtShipyard; `native/crates/sim_core/src/agents/ship/mod.rs` constants 150/60/30, morale threshold 40 and config tick multiplier. `native/crates/sim_server/src/engine/apply.rs` N21 FIFO/admission, `FacilityStorage.dock_queue`, `commit_dock` N9 money conservation.

1. `godot/scripts/sim/phase2/unified_ship_ai_execution.gd`: the one N84 action dispatcher now starts the nullable `dock_attempt_start_tick` on the real Dock attempt (not during N14 transit), checks 150 ticks for an active N104 contract, 30 for morale under 40 and 60 otherwise, multiplied by source tick_multiplier. Success / physical docking clears the clock. A timed-out speculative goal drops its BT, cancels the real N90 pending slot only, retains already-physical inventory, and returns to original source goal competition rather than halting the N158 world. N91 construction and retrofit speculative goals also fail/replan without world freeze.
2. **Paid N104 timeout guard:** `active_contract_id` with escrow and potentially real cargo cannot be erased as a speculative goal. On source timeout N84 records the event, clears only the N21 waiting cursor and resumes its persisted mission; original full contract rerouting remains a separate unverified parity gap. No money/goods/contract cancel is invented.
3. `godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd` and N158 `dock_queue` phase: when no actual facility owns a nonempty FIFO, skip the costly full N39 schema/N9 ledger Apply and deep-copy of the whole World; preserve every real waiting queue admission, stale prune and paid receipt. N158 still observes a snapshot; this is a safe fast path, not a benchmark-based optimization claim.
4. Manual UI `request_ship_dock` now calls **N39.apply_native_n21_manual_dock** against the last committed native tick; it uses the same source N21 queue ranking, real source fee/discount, existing N9 ledger transfer and immutable dock receipt. The user-provided operation ID is returned as request metadata, while authoritative receipt ID is `n21:dock:<ship>:<tick>`. If the port is occupied / queue has priority, manual request fails closed without publishing a shadow queued user BT, money, or receipt. Manual Dock before the first committed tick is correctly rejected. Automatic N84 dock queue is unaffected.
5. `n39_native_world_production.gd::apply_fleet_logistics` explicitly refuses legacy `action == "dock"`; manual warehouse `load/unload` and free physical `undock` remain supported. This removes the old unpriced N15 Dock bypass even from direct N39 callers.
6. `godot/tools/p2_v4_source_gate.py`: additional read-only checks for N84 original constants, N38 nullable cursor, safe paid N104 handling, manual N39/N9 Dock and absence of legacy free Dock.
7. **Deferred fixtures authored, NOT RUN:** `p2_n21_dock_timeout_source_check.gd` (150/60/30 and ×multiplier, arrival, transit, JSON cursor) and `p2_n21_manual_paid_source_check.gd` (real paid berth, N9 fee, immutable receipt, no replay, no queue jump).

## Verification performed, limits

Reread the seven changed/new source/gate artifacts at GitHub HEAD: structural delimiter and quote integrity in six GDScripts, terminal newline, no NUL, expected source callsites. **7/7 static check passed.** This is NOT proof of syntactic acceptance by Godot's parser; no gameplay, soak, source-gate execution, save/load or Windows test has run.

## Residual correctness risks / final source audit

- Original Rust N84 timeout **policy** exists. For an active prepaid N104 contract, the present continuation is a safe retry of the same persisted BT, not a complete original N81/GOAP alternative contract path. Never claim exact alternative-route parity from the timer alone.
- Manual Dock now is physically paid but only runs after the first committed native tick; this avoids pseudo-tick fees or a second persistent manual queue. Manual user command ID is not itself a new N9 operation ID; the source receipt is deterministic.
- Real N21 facility condition defaults to 1.0 when a legacy facility does not yet carry N156 `condition`; when N156 writes the source condition, the exact fee formula reads it. No balance modification made.
- The N158 empty-FIFO fast path avoids full N39 validation but still takes one `world_snapshot()` for inspection; no runtime performance metric is claimed.
- Original N21 timeout and manual paid Dock must pass the one final full Godot 4.7.2/Windows acceptance. Needed complete A (real N153→N104→N14→N21→N9), B (colony), V (Head), G (one Windows executable), and a saved midqueue N38 scenario.
- Chat3 N113 source-candidates lease is RELEASED and was not overwritten. No extra tech, UI, AI balance, facilities or free hulls were added.

**Do not call SOURCE_INTEGRATION_COMPLETE or gameplay VERIFIED merely because these commits exist.** Continue with the latest V4 acceptance matrix and only then trigger one coordinated Godot/Windows check.

Lease: `godot/docs/phase2/leases/20261114-chat1-n21-timeout-source-fix.json`; released after this report.
