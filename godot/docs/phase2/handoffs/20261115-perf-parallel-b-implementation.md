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
