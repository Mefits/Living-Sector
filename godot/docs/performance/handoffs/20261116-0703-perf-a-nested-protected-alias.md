# PERF A · nested protected aliases · 2026-11-16 07:03 MSK

Branch: `integration/perf-astra-5-workers-20261116` / draft PR #262.

CODE COMMIT: `8640c0449d7c2d8a9096280c4fd7d0b7f1e8e4e5`
TEST COMMIT: `f7e0411775ab4adee215be83f3fd4d44db619fb1`

Files:
- `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`: reject shared protected nested Dictionary/Array values even if top-level market rows are detached. Prior comparison could miss in-place stock changes through a shared nested dictionary. No production wiring.
- `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`: negative shallow-row stock alias and deep nested array alias; positive independent deep copy.

TEST EXECUTED: NOT RUN (Godot unavailable). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Static inspection: existing Observation preload and method signatures unchanged; no new preloads, no production runtime modification. Performance benefit not measured; safety check adds traversal overhead in this diagnostic-only guard.

Invariant: full Schema oracle remains required. No N39/N9/N158/SaveState production changes; no balance or cadence change. GitHub Actions not launched.

NEXT: run targeted test in Godot 4.7.2; compare local guard with full Schema oracle and measure diagnostic overhead before any shadow N150 integration. Coordinate N150 commit boundary with D; do not enable by default before parity.
