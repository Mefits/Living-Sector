# PERF C handoff · 2026-11-17 · stale N84 envelope
Code commit: dbed35e02ea54af7b102759a585f59a06f067b14
Test commit: 7265addfdebd5106473ebdf74735b2cd9b148a1e
Files: godot/scripts/sim/phase2/unified_ship_phase.gd; godot/tests/p2_perf_c_n84_stale_envelope_guard.gd

## Change
The previous N84 proposal cache trusted ship_next_token and fleet size as a proxy for all other ships' identity/transit. An in-place transit/identity edit with the same token and cardinality could silently reuse a stale max_token and bypass envelope checks. The live envelope is now validated every preview; only the selected ship is deep-restored. No changes to N39/N9/N158.

## Evidence
CODE_COMMITTED; TEST_ADDED_NOT_RUN. No Godot runtime or same-seed benchmark executed. This correctness fix removes the unproven O(1) envelope reuse and may regress N84 CPU; do not count it as an acceleration. Static negative test checks that the unsafe branch cannot return. Behavioral oracle (including mutated nonselected ship and paid contract/fuel/cargo), N38 restart and tick100/600/900 source timings remain required.

## Next
Introduce an authoritative mutation version for fleet identity/transit only with the C/A ownership contract, or keep live validation. Measure ship+dock paid tick CPU and identify a proven growing site before further optimizations.
