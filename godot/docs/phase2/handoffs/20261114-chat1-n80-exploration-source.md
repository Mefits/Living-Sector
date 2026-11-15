# Chat №1 continuation — N80/N103 exploration and ice mining source adapters

**Date:** 2026-11-14  
**Repository/branch:** `Mefits/Living-Sector`, `integration/godot-phase2-unified-20261113`  
**PR:** https://github.com/Mefits/Living-Sector/pull/249  
**Status:** **SOURCE_PREPARED / CODE_UNVERIFIED / NOT_LIVE_WIRED**. No Godot run, F5, tests or GitHub Actions.

## Source reference and delivered files

- Frozen Rust `crates/sim_core/src/agents/ship/behavior.rs`: `smart_idle_fallback`, `try_build_explore_bt`, N80 scoring and ice mining selection. `components.rs` fixed constants: 240 idle ticks; 2,500 CR; 40% fuel minimum; 5 seconds at destination dock. No change to thresholds.
- `godot/scripts/sim/phase2/unified_n80_ship_exploration_stage.gd`: detached N80 proposal for only real N140-fired idle ships. Uses `native_ship_idle_policy.gd`, `native_ship_goal_policy.gd`, `native_behavior_tree.gd`, authoritative real N39 built **reciprocal** `gate_link` and actual systems, N4 directed legs and a physical destination N21 station. Produces serializable `Undock -> Travel -> GateJump -> Travel -> Dock -> DockDwell(5) -> Undock` (omits zero-length travel legs). Checks fee affordability; N108/N9 still authoritative. Real dock and gate may share one nav location. No free/unbuilt gate, no fabricated inter-system edge and no physical change at proposal time.
- `godot/scripts/sim/phase2/unified_n80_ship_mining_stage.gd`: detached N103/N80 ice-mining candidate using `native_ice_mining_policy.gd`. Gets ice richness from actual N39 bodies, same-faction dockable buyer and its existing wallet, real ship-observed source quotes, real N4 directed round-trip, original ship fuel/cargo state. Produces `Undock -> Travel -> Mine -> Travel -> Dock -> Sell -> Undock` when source selectors permit. No cargo, resource, money or tick mutation here.
- Deferred fixtures: `godot/tests/p2_n80_native_gate_explore_check.gd`, `godot/tests/p2_n80_native_mining_source_check.gd`. Cases include real GateLink, common gate/market endpoint, missing pair, insufficient credits, unreachable leg, sleeper; for mining: real deposit, stock exhaustion, zero buyer cash, missing observed quotes, missing return route and sleeper.

## Source-only verification

Readback of four new/updated GDScripts from the GitHub branch: complete UTF-8 contents, no NUL, final newline, balanced parentheses/braces/brackets and quotes. **These are static textual checks only.** No Godot parser, gameplay, deterministic scenario or post-save execution has run, per Phase2 integration freeze.

## Blockers before source can be called LIVE

1. Chat №3 has `IN_PROGRESS` V2 crisis lease on shared `n39_native_world_production.gd`, `n39_native_world_schema.gd`, `n158_production_runtime.gd`. Deliberately did **not** edit them. N158 currently calls the real N83 free-trade planner and N140/N84, but not these N80/N103 source stages.
2. N84 `unified_ship_ai_execution.gd` skips uncontracted `explore` / `idle_seek_station` goals. Its non-contract Dock/Undock path and N158 command-Apply authorize `trade_route` (or separately paid construction/retrofit), **not** `explore`. Must enable only a valid persisted N80 tree with an actual N21 market/port, never a generic unchecked dock.
3. Mining's N97 `Mine` action has a source N90 service Apply, but the `Sell` leaf is currently authorized by N83 only for `trade_route`. Need original mine-goal legal sale through the same exclusive N90/N97/N9/N146 command path, not a second market or cargo transaction. Confirm N14 fuel/leg availability at assignment, saved BT continuation, and source price/route parity.
4. Frozen clean seed contains no built gates. This stage **must not** force exploration on startup; construction and explicit link must happen physically first. Do not invent seed gates, new tech gating, automatic gate linking or gameplay balance.

## Handoff and next block

After Chat №3 releases central file claims, take a new scoped lease and wire N80/N103 in **one** N158 ship decision phase: N83 contract/trade precedence, N140-fired checks, N80 idle/mining proposal application only through N39 `apply_ship_phase`, N84 cursor execution, legal N21/N90/N97/N108 command-Apply, N38 save/reload. Check absence of duplicate money, mined ice or flights. Complete any remaining Rust source domains **before** user's one project-wide Godot verification. Do not claim SOURCE_INTEGRATION_COMPLETE or pass status for Phase2.

**Lease:** `godot/docs/phase2/leases/20261114-chat1-n80-ship-exploration-source.json` (released after publishing this handoff).
