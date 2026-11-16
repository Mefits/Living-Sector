# PERF C handoff — 2026-11-16 03:59 MSK

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

- CODE COMMIT: `9c042ccf857f9b9373971ff07ac3949dee6f4b60`
- TEST COMMIT: `c9b69fc5f1a3fecd59d525a86cf3c62fb14cb570`
- Files: `godot/scripts/sim/route_graph.gd`, `godot/tests/p2_perf_c_native_route_upsert_oracle.gd`.
- Replaced repeated linear scans of native-seeded adjacency lists for SQL-style reverse upserts and N142 chart INSERT OR IGNORE with per-origin destination-to-index lookup. Existing edge order, overwrite precedence, distance, system_id and final sorting remain unchanged; index is local to load_worlds and never persisted or shared with World. Failed loads still leave active graph and route cache untouched.
- Added native source-order oracle with reversed repeated edges, N142 chart generation, cached/uncached parity, and failed-load rollback.
- TEST EXECUTED: NOT RUN (no local Godot); CODE_UNVERIFIED. No benchmark or TPS/FPS improvement measured. GitHub Actions not launched.
- NEXT: run new oracle and prior C FIFO/tie tests in Godot; compare native graph build time on dense realistic source fixture; then evaluate indexed N153 eligible-ship invalidation under paid contracts and N38 restart.
