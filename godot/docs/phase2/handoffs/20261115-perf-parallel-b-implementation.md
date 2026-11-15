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
