# PERF A — cross-type mutable alias detection (16.11.2026 09:06 MSK)

- CODE SHA: `7fe97750dc3e3a7fe19ca528db41516b76042372`
- TEST SHA: `93b10ba02346305ce9ac198dc5345cef3e61e699`
- Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
- Changed `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`: recursive alias detection now searches nested Dictionary and Array containers across type boundaries, rather than only descending when both values share the same container type. Scalar leaves are skipped. This closes a protected-field alias escape when a mutable Dictionary is moved into an Array, or an Array into a Dictionary.
- Changed `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`: negative cases for both cross-type directions, plus independent deep-copy write violation.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. Static source inspection only. No Godot runtime available here; no measured TPS/FPS benefit. Cross-product traversal may be costly on large nested structures: guard remains isolated and is not enabled on production N150 boundary.
- No changes to World/Schema oracle, Ledger, N158, N38, balance, CI, or workflows.
- NEXT: run targeted Godot test; benchmark guard on realistic N150 market rows against full Schema oracle; then coordinate shadow wiring with D only if overhead acceptable. Investigate cyclic container protection before enabling on untrusted arbitrary graphs.
