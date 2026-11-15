# Chat №2 N153 II-C — working record 2026-11-15

- Branch: `feature/perf-parallel-b-n153-indices-20261115`, Draft PR [#258](https://github.com/Mefits/Living-Sector/pull/258).
- Original coordinated SHA: `823f32379b10bfefae5a5cebb1c0c0e622509f72`; source dispatch oracle: `fb8dc0c3a9df3fbdb722a13d214be72ab67bf9df`.
- Change: per-propose sorted posted IDs, posture tuple cache and per-contract directed N14 leg geometry by origin. Original N4.shortest_path remains the only route solver. No cross-tick or N38 lifetime.
- Contract and ship gates retain native loop ordering, exact rejection counting, final fuel/credits/stock/sensor/profit/BT. No promise of performance benefit until same-runner A/B.
- New regression tests: whole output exact oracle parity against frozen pre-change dispatch on real N104 funded offer and negative mutations; selector-valid scale clones (24/100/500) from original Hauler, not authoritative world inserts.
- Acceptance: separate own workflow, real Godot 4.7.2 on unmodified original seed 420+N38 restart360, then 900; same runner baseline/new 420, uploaded logs.
- Verification status: PENDING CI; do not mark green or merge. Needs profile and further refactor only if A/B warrants it.
