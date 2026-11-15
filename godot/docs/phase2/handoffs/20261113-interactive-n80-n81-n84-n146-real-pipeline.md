# Living Sector P2 — N80 → N81 → N84 → N146 integration
**Date:** 2026-11-13, interactive chat. **Branch:** `integration/godot-phase2-unified-20261113` / Draft PR #249.

## What is ACTUALLY wired in the shared simulator
- New `godot/scripts/sim/ships/ai/native_behavior_tree.gd` ports **Rust N84** `native/crates/sim_core/src/ai/behavior_tree.rs`: `Sequence` processes one child per tick, persists index, resets on terminal status; `Selector` retries from first child; explicit boolean `Condition`, domain `Action` and persistent serializable tree. Bounded validation and N38 JSON integral-cursor restoration. Leaf side effects are delegated, never implicit.
- New `godot/scripts/sim/phase2/unified_ship_ai_planner.gd`: uses **existing N80** `native_ship_goal_policy.choose_goal` (source preferences), **existing N81** `native_goap_planner.plan` (actual Dijkstra) and **existing N153 source** `n153_native_ship_bt_planning.compile_plan_to_bt_actions`, with **N4 real directed route legs**. Rejects missing/failed goal/plan or plans requiring unintegrated paid refuelling/refit. No new custom planner.
- `unified_n153_contract_dispatch.gd` continues to use exact N153 source contract selection with source quotes and native ship eligibility, but **only** proposes accepting offers when a real N80/N81/N84 plan exists. Attaches `ai_bt`, N80 score, N81 cost and personality provenance to proposal.
- **Known source parity limitation:** frozen 24-ship JSON does not carry Rust's sampled random ship personality. N80 uses the *original* Rust-derived `Personality.for_class` fallback explicitly labeled `native_class_fallback_pending_seed_rng` (NOT fake full parity); precise Rust seeder RNG replay is a future task. No global market memory/pretend cargo is injected.
- `N39.accept_autonomous_delivery` persists N84 tree and N80 score in the SAME source ship row only after source N104/N9 funded admission, then validates complete World + Ledger; `N39 Schema` validates BT save structure.
- The N158 **factions** phase now places real `AcceptContract` commands in original **N146 `native_sim_command_buffer.gd`** and drains them through `N39.accept_autonomous_delivery`. No second Board or Wallet is introduced.
- New `unified_ship_ai_execution.gd` ticks each active accepted ship's **one N84 leaf per tick**; a supported `Travel` emits original N146 `BeginTransit` only after authoritative N14 `ShipPhase.depart` preview; accepted commands are cross-checked against the exact native `arrival_tick`, then the single `N39.apply_ship_phase` commits the physical fleet and saved N84 cursor together.
- The old hand-written "contract → shortest_path → depart" loop is removed from N158 ships phase. N146 leaves for **Dock/Undock/Buy/DeliverCargo** remain **Running with blocked reason**, not silently successful. Hence no fictitious warehouse/cargo/paid delivery/settlement.
- N84 execution validates held N104 contract is accepted/picked_up and `fulfiller_id` matches the ship; older accepted ships with no BT remain idle and marked for native replan rather than corrupting old saves.
- N38 checkpoint restoration normalizes only `N84 Sequence.index` and `last_plan_tick`, preserves cargo and real floating fuel/market stock.
- New fixture: `godot/tests/p2_n80_n81_n84_n146_pipeline_check.gd`. Tests original N84 sequence/selector semantics, JSON cursor preservation, real 24-ship/N4 world with source N80+N81 goal plan, N146 `BeginTransit` acceptance on a detached test-only accepted-contract fixture, original N14 movement, idempotent no-reissue in flight, unchanged authoritative World. Fixture does NOT commit fabricated contract/goods into the game.

## Validation status
- GitHub static source readback: **PASS** on all changed files (balanced strings/brackets, no NUL bytes, every preload file exists, N80/N81/N84/N146/N14/N39 hook chain present).
- **GODOT NOT RUN. TESTS NOT EXECUTED. NOT RUNTIME ACCEPTED.** No GitHub Actions/Windows build triggered from this chat.
- Needed on user Windows portable Godot 4.7: `godot --headless --path godot --script res://tests/p2_n80_n81_n84_n146_pipeline_check.gd`; also previous `p2_n153_live_contract_dispatch_check.gd` and F5 new world, save/reload in mid-transit. Capture exact first parser error and trace before declaring success.

## Next free large block / limitations
**NEXT**: autonomous N21 real dock admission → N97 native paid source purchase → N15 physical pickup receipt → N84 leaf success → N14 route to actual receiver → N15 delivery → N104 receipt-confirmed settlement/refund. No fake shipment/instant cargo or second N9 Ledger. Ensure same World+Board+Ledger atomic transitions and resume on save.
Other known gaps: N80 source per-ship seeded RNG, native replan cadence/GOAP adaptive repairs, N84 selector condition coverage, full N88/N90 leaves, live N150 diplomacy and reputation, GOAP fuel tank refill by physical paid service.
No new manual ship buttons. Existing manual N14/N21/N15 APIs remain conserved for later/debug.
