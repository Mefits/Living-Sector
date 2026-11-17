# C — N84 Travel preview: owned fleet, 17.11.2026

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `98804f5f65e467d671afd4f90555e8aeacced534`.
TEST COMMIT: `c894169346a86f9bc58ac89260a9de488b898e4a`.

Files:
- `godot/scripts/sim/phase2/unified_ship_phase.gd`: `depart()` now returns the exclusively owned, already deep-detached `ShipState.restore()` fleet instead of duplicating every ship again after `motion.depart()`. This is a real N84 Travel → N14 departure-preview path; N146 still authoritatively applies the command. No World/N9/N158 changes.
- `godot/tests/p2_perf_c_depart_owned_preview_oracle_20261117.gd`: independent old full-copy snapshot oracle, World isolation for nested cargo/transit and sleeping ship, source token ordering, invalid route negative.

CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No local Godot runtime used; no CI triggered. No measured speedup, no 900/2600 or Windows soak proof. Source-level saving is one full detached-fleet deep copy per successful preview; the earlier `ShipState.restore` copy remains mandatory. Potential mutation of returned proposal by downstream consumers must be checked by targeted runtime and N38 parity before acceptance.

Next: run targeted test; measure N84 Travel preview count/time and ships+dock CPU ms/paid tick same-seed 100/600/900; exact N9/N39/N38/BT/RNG/contract/cargo parity and paid transit before enabling any further ownership changes. Do not repeat `99ab25e9` or `1676db61`.
