# Chat №3 / N113 — source Rust strategic hysteresis in real N147 colony workforce

**Date 2026-11-14 · shared PR #249 · integration/godot-phase2-unified-20261113**

## Original source and objective

Rust `native/crates/sim_core/src/strategy/director.rs::retain_or_switch` owns the leader's strategic memory. Default superiority **1.20×**; a *viable* incumbent can be displaced by a stronger alternative only after **two different real decision cycles**. An unavailable incumbent switches immediately; a paid native supply plan is not revoked; a genuine viable life-support crisis can bypass hysteresis. Ties choose the lexically smaller action/target. `strategy/coordination.rs::run_cycle` obtains freshly scored options; N147's actual physical migration is commissioned only after the same Head selects `migrate_colony`. Storing a preference alone never creates a Passenger N104 contract.

Previously Chat2's B1–B4 SOURCE_WIRED was released and Chat3 connected N147 to revalidated N134 Head/N39. The remaining defect was that a viable previous N113 strategy could never legally yield to migration after sustained >1.20 priority: N147 rejected **all** other incumbents permanently. This block introduces real conditional switching but **does not fabricate unrelated strategy candidate scores**.

## Changes already in shared branch

- `aa66522` — **new `godot/scripts/sim/phase2/unified_n113_strategy_switch.gd`**, pure faithful source `retain_or_switch`. Current source-validated candidate set, stable ranking, 1.20× exact boundary, two distinct decision cycles, single persisted `pending {kind,target,consecutive_cycles,first_seen_tick}`, locked native funded supply, incumbent refresh, no phantom money/World, no repeated confirmation in one tick.
- `851c9b7` — `unified_n147_colony_head_grant.gd` now computes the **current authentic** N134 N111 ready Build/Deliver score from actual Head `alternatives` and Director profile, using frozen Rust `director.rs::option_score` (special capability/build scores, net-value logarithm, priority age, site adjustment). Its only competing proposal is a source-preflighted N147 migration score 60. Supplies the pair to the exact N113 helper, returns an unconfirmed memory update or an authorized `migrate_colony` Head. Source state is read only.
- `5b983e7` — `n39_native_world_production.gd::post_native_passenger_migration` saves an *unconfirmed* N113 memory into the **existing N39 World** after Schema and canonical N9 wallet equality checks, returning `N113_REAL_STRATEGY_NO_N104_CONTRACT`. No new N9 payment, posted contract, fabricated ship or additional clock. Only after the second authorized decision does the original `NativePassengers.post_migration` publish the same N104/N9 funded Passenger and commit N113 memory atomically with escrow.
- `8344e38` — **enforces only genuine 60×mult coordinated source cycles** at N39, so arbitrary per-frame calls or tick 1 cannot accelerate the two confirmations.
- `d330da1` — new deferred pure `godot/tests/p2_n113_strategic_switch_check.gd`: first/second cycle, same-tick replay rejection, exact 60/50 threshold equality, reduced benefit reset, unavailable incumbent immediate decision, paid supply lock, emergency life-support bypass, deterministic tie and no available candidate.
- `0362078` — expanded deferred `godot/tests/p2_n147_native_head_grant_check.gd` with *current real source N111 build alternative* versus N147 migration: 43-point capability incumbent, 60-point migration, first cycle pending without mutation, second cycle authorized, same-tick replay rejected, refreshed higher build capability cancels pending; legacy intent and crisis/funded protections preserved.
- `43bde6a` — V4 source-gate now checks these N113/N147/N39 live links (a static link is **not** a runtime PASS).
- `0cd4817` — V4 gate recognizes real N21 FIFO N39+N158 after chat1 released its lease, not stale legacy DockingRegistry.
- `c4b17a1` — V4 `P2_V4_FINAL_ACCEPTANCE_MATRIX_RU.md` reconciled with actual completed Chat1 N21 and N113 source links.

## Coordination

Chat1 N21 FIFO previously owned shared N39/N158. We created our own claim `20261114-chat3-n113-strategy-hysteresis.json` while its lease was **IN_PROGRESS** and authored **only independent pure helper/test files** until Chat1 marked its lease **RELEASED**. We then fetched the current N39 blob SHA and modified **only the N147 pending/strategy source block**, leaving Chat1 dock queue, N9 fees, seed, AI and phase order untouched. N158 was not modified. No conflicting overwrite/force push.

## Verification and exact remaining limits

**SOURCE_WIRED (current N134 Build/Deliver vs N147 migration) / CODE_UNVERIFIED / RUNTIME_UNVERIFIED.** All source changes and test scripts were authored and read back; no Godot, F5, Windows, headless, script execution or Actions by user instruction. No balance, tick duration, ship handling or market formula was changed. The 1.20/2 constants are from original Rust.

**Unresolved full strategy parity:** This N147-specific source adapter can re-score the **current verified** N134 Build/Deliver option. It conservatively retains a historically committed *different* supply target, science/research or expansion incumbent if its independent original Rust candidate is not reconstructed by today's construction-only N134 source bridge. Rust `coordination.rs` compares research readiness/charter/occupied workers, prior supply from `compare_director_target`, and colony proposals before the N113 vote. Those additional authentic candidate sources must be wired before claiming the **entire** N113 strategic ecosystem is SOURCE_COMPLETE. Do **not** substitute stale stored scores, arbitrary invented 60-point bonuses, or a second AI/World.

A further source and eventual runtime check must prove N38 save/reload **between** the two N113 decision cycles and N104 physical boarding/arrival/paid receipt after authorization. N21 FIFO live queue, Dock wait/timeout, N92 Food/Water, N100/N121 and Windows final integration should be run together **once**, after all source gaps close. Static readiness is not a game/Windows PASS.

**Safe next step:** Complete the original research/expansion/prior-supply offer reconstruction in N134 using authoritative World and Rust score formulas, feed it into this *one* N113 helper, then one coordinated Godot acceptance. No user mechanic/balance changes until source integration is finished.
