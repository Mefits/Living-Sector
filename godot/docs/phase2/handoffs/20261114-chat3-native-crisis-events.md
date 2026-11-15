# Chat 3 / V2: Rust Bundle(S) warning transitions (2026-11-14)

Branch: `integration/godot-phase2-unified-20261113` · PR #249

## Frozen source
- `native/crates/sim_server/src/engine.rs::scan_crisis_events` executes after `market::tick_markets`, before faction/ship settlement.
- Original `WorldTuning`: market shortage **>=200**, recovery **<=50** ticks; facility starving condition **<0.3**, recovered **>0.5**.
- This is notification hysteresis, **not** `strategy/director.rs::environmental_events` N133 industrial damage (no confirmed runtime call). No balance/mechanics changes.

## Changed (real code on shared branch)
- `424f890`: `unified_native_crisis_events.gd` pure, deterministic Rust event staging for markets and facilities; validates source state without changing stock/credits/condition.
- `ce29f2d`: existing `unified_market_phase.gd` runs warning scan **after real N150 market pass**, persists `crisis_notified` within its existing market `history` to **one N39 Apply** and returns `crisis_events`. Old P2 history lacking this flag uses empty Rust-default dict.
- `b6c7dde`: `p2_native_crisis_events_source_check.gd`: 199→200, no repeated events, <=50 recovery, strict facility boundaries, no mutation/invalid source.

## Acceptance truth
**MARKET_STAGE_SOURCE_WIRED / CODE_UNVERIFIED, NOT FULL BUNDLE(S).** Pure stage market flag is used by live N150→N39 proposal, but **N158 does not yet publish returned `crisis_events` to the UI/server event sink**. Already persisted alert flags must be surfaced from current state on first consumer hookup, not discarded because the transition happened earlier. Facility warning proposal is **NOT committed**, since actual `starving_notified` belongs inside N39 World. Static delimiter/preload/line ending checks pass. Godot/Windows/Actions **NOT RUN** by user instruction.

## NEXT when user says «Продолжай»
1. Recheck HEAD and leases. Chat 1 currently owns N39/N158.
2. Once released, add one atomic source apply for facility `starving_notified` to real N39 FacilityOperations; pass market+facility events through **existing** N158/EventQueue/Observer, N38 snapshot, no parallel event owner.
3. Compare actual Rust phase order `markets→crisis→factions`, restore/replay, validate one complete Godot integration at final checkpoint. Do not start Actions in intermediate iterations.

No edits to N39/N158/Schema/N9/N104 were made here.
