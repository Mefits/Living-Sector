# Chat №2 N153 II-C — working record 2026-11-15

- Branch: `feature/perf-parallel-b-n153-indices-20261115`, Draft PR [#258](https://github.com/Mefits/Living-Sector/pull/258).
- Original coordinated SHA: `823f32379b10bfefae5a5cebb1c0c0e622509f72`; source dispatch oracle: `fb8dc0c3a9df3fbdb722a13d214be72ab67bf9df`.
- Change: per-propose sorted posted IDs, posture tuple cache and per-contract directed N14 leg geometry by origin. Original N4.shortest_path remains the only route solver. No cross-tick or N38 lifetime.
- Contract and ship gates retain native loop ordering, exact rejection counting, final fuel/credits/stock/sensor/profit/BT. No promise of performance benefit until same-runner A/B.
- New regression tests: whole output exact oracle parity against frozen pre-change dispatch on real N104 funded offer and negative mutations; selector-valid scale clones (24/100/500) from original Hauler, not authoritative world inserts.
- Acceptance: separate own workflow, real Godot 4.7.2 on unmodified original seed 420+N38 restart360, then 900; same runner baseline/new 420, uploaded logs.
- Verification status: PENDING CI; do not mark green or merge. Needs profile and further refactor only if A/B warrants it.

## Verified live CI progress

- Commit `fe93117e8a5de753ddf2cb05178c15f142001965`; first CI run: https://github.com/Mefits/Living-Sector/actions/runs/43728288327.
- Godot 4.7.2 editor/import, oracle parity on real funded N104 delivery and negative world copies, 24/100/500 scale fixture, existing N153 paid-accept and N4 route parity: **PASS** (CI step 4).
- Full original economics N38 restart360 and 420 ticks: **PASS** for original baseline and candidate on one runner; checkpoint lines after stripping elapsed wall time matched byte-for-byte (CI step 5).
- 900 ticks including tick825: **IN PROGRESS** at reporting time. No speedup claim until numerical logs are available; 420 is a single paired wall-time observation, not a statistically established gain.
- The scaled fixture reuses original class, faction, market, directed graph, fuel and paid source offer; unique synthetic ship IDs exist only inside selector test data, not in canonical N39 ledger/World.
- Read-only world, source winner, BT, blocked reasons/counts, and deterministic order tested by exact oracle equality. N39/N9/N4 production interfaces untouched.

## Second (final for this iteration) A/B on `fe8b7808b9ab615db0213c78107b20711b4cf734`

CI: https://github.com/Mefits/Living-Sector/actions/runs/43729181807 — **PASS, Godot 4.7.2**.
- Exact frozen source-oracle output parity, **21 scenarios**, including original actually funded N104 offer, stock/funds/reputation/fuel/route/busy/cargo, expiry, order and all published rejection counters/BT: PASS.
- N153 selector-only scale with original directed N4 positions, N104 offer and prototype of the real hauler; the clone IDs stay test-local (not canonical World insertions):
  - 24 ships: baseline `1424 us` → candidate `1139 us` (1.25x).
  - 100 ships: baseline `51389 us` → candidate `3795 us` (13.54x).
  - 500 ships: baseline `344383 us` → candidate `19993 us` (17.23x).
  - One measurement per arm; only N153 propose, NOT entire game TPS.
- Original unmodified seed 420 ticks + N38 disk restart at 360: candidate `69416 ms`, baseline `68415 ms`; all `P2_STAGE2_CLEAN_CHECK` snapshots equal after removing wall time, no proven whole-sim speedup (candidate ~1.5% slower in this single noisy run).
- Original unmodified seed 900 ticks with N38 restart360 and tick825 regression: `P2_STAGE2_LONG_NATIVE_PASS tick=900`, `235919 ms`, 24 real ships, 4 contracts, 4035 N9 receipts at tick900.
- Core optimization `fe8b780`: after N153.select_contract returns *actual exact profit*, skip N81 GOAP/BT only when an existing winner has >= profit. Frozen winner comparator is strict `>`; no skipped bid could ever change winner. When no winner exists ALL N81 gates/rejection accounting still runs. When a winner exists the `ship_blockers` dictionary is never published, so losing N81 results cannot change observable counters/reasons. Real funding/stock/treaties/knowledge/route/fuel checks before N153 are unchanged.
- First index-only candidate `87d16f6` on same host (CI 43728288327): whole sim baseline `71666 ms`, candidate `78860 ms`; this motivated dominated-BT optimization, not claims of faster whole game.
- **Risk:** 420 original fleet size is only 24 with few posted offers; N39/ledger dominate whole-simulation time. No meaningful whole-game FPS/TPS win established; a 10k-tick soak and multi-seed/replicated benchmark remain unverified. N18/EventQueue untouched. PR remains Draft; green only coordinator after merge.

## Final B5–B7 / Gate report — 15 Nov 2026

**Latest tested implementation:** `f633baff928ff93bafe4f2648137e15834786690`; dedicated CI [#43739624582](https://github.com/Mefits/Living-Sector/actions/runs/43739624582), **PASS**, Godot `v4.7.2.stable.official.ed1daf0bf` on one ubuntu-24.04 runner. No production files beyond N153 dispatch/own index touched.

### B5 — DONE-TESTED
- Reuse contract-scoped immutable `offer` and `controllers` DTOs after the first fully ready ship; one-call `location→system` resolver memo, rebuilt every `propose`, including immediately after N38 reload.
- Keep N153's real `quoted_payment`, `top_up`, payer balance, source purchase quotes, actual stock/fuel/permissions, ship-specific bonus and credits revalidated in the exact original order for each ship.
- N80 price knowledge: no deep copying for read-only N153 selection; if a ship is **physically at source**, shallow-duplicate only the top-level knowledge dictionary and replace the source's observed commodity with the current **actual** market quote. No write to persisted ship price history. Native selector and N81 remain unchanged.
- Test-only frozen original dispatch parity: **30 scenarios**, including true N104 paid offer, invalid memory/source quote, at-source knowledge, altered knowledge between calls, duplicate offers, missing funds/stock, busy/cargo/fuel, pirates/faction/route, source selector profit tie-break and exact BT/blocked counts. Output dictionaries identical; input World unchanged.
- Original directed graph and paid contract are reused; 24/100/500 test-only ship prototypes are NOT paid N39 simulation ships. The 500-ship benchmark measures N153 alone, not whole-game TPS.

### B6 — NO-CHANGE (measured, not a code fix)
- Original N39 World + exact N9 account import, direct N18 due-cycle at tick5: **3 real markets**, **15 facilities**, **3 populations**. Upper bounds: **45 facility checks and 9 population checks** per due cycle. `first_us=700`; six further equivalent calls took `3705us` (~618us/call); every `5×multiplier` ticks.
- N18 source sorts IDs and scans those small sets; its costly station planner/recipes also executes. An index would add maintenance, yet there is no evidence the repeated small roster scans are a meaningful whole-game bottleneck. **No N18 production change**, pending future increased-scale observed profile. No claim that ~0.6ms represents pure roster-sort cost.
- N18 probe verifies exact source plan deterministic repetition and no World mutation.

### B7 — NO-CHANGE (not connected to live tick path)
- Code audit: `n158_production_runtime.gd` has no `EventQueue`/`take_due`; N39 notes its command processing is **not** a future EventQueue. The active original seed has no live scheduler queue count to profile. The `event_queue.gd` class was left untouched.
- Synthetic regression verifies duplicate active IDs denied, cancel/reuse, N38-style snapshot/restore, due tick/phase and deterministic entity/sequence ordering. **1680 synthetic empty polls / 706us** is *not* live event-queue profiling; it only demonstrates the low cost of empty polls. A heap/bucket optimization is unjustified without live pending events.

### Final acceptance / performance (single CI runner)
| Check | Outcome |
| --- | --- |
| Godot 4.7.2 editor import/parser | PASS |
| Native N153 oracle | 30/30 PASS |
| N153 24 ship fixture | 1248 → 989 us |
| N153 100 ship fixture | 44338 → 3065 us |
| N153 500 ship fixture | 273168 → 14892 us (18.34× selector-only) |
| Live real N153 N104 paid acceptance + N4 route cache parity | PASS |
| Native N18 + EventQueue conditional diagnostic | PASS |
| Same-host full original seed 420 ticks + **N38 restart360** | baseline 58805 ms; candidate 57144 ms; published checkpoint lines identical after wall-time strip |
| Same original seed 900 ticks / N38 restart360 / regression tick825 | PASS, 235794 ms; tick900: 24 ships, 4 contracts, 4035 N9 receipts |

**Caveats:** The 420-tick whole-sim result is one paired observation (~2.8% faster), not a proven sustained FPS/TPS improvement. Not tested: 10k ticks, broad seeds, complete byte-for-byte world/ledger/BT fingerprint at every tick, or performance at 100/500 *canonical* N39 ships. PR remains Draft and **must not be merged** except by coordinator after integrated smoke (especially after PR #257 lands). The old B5 status above describes the earlier snapshot; this section supersedes it.

### Scope / integration
Touched this iteration: `godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd`, `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`, `godot/tests/p2_parallel_b_n153_parity_check.gd`, new `godot/tests/p2_parallel_b_n18_eventqueue_probe.gd`, and **own** `.github/workflows/p2-parallel-b-n153.yml` and B handoff files. **Not touched:** N18 runtime, EventQueue runtime, N39, N9, N4 route_graph, N158, PR257 files or shared CI. Board remains ORANGE; green only coordinator after review/merge.
