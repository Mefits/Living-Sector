# PERF D · 17.11.2026 · N150 owned seed transfer

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `5db52a685d6827bd4dc531d8570b9dd088de92ba`
TEST COMMIT: `da37118d31631c7bc96f945d939340f203907ff9`

Files: `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`; `godot/tests/p2_perf_d_n150_owned_seed_transfer.gd`.

The existing N150 paid tick deep-duplicates the whole market before mutating it. On first tick with empty seed demand, it previously deep-duplicated the *already detached* pricing demand map a second time. Now it transfers that owned map to seed_demand; the pricing demand map is replaced with a newly computed map later in the same tick. No shared mutable alias survives. First-tick and second-tick semantics, price source, cadence, and market history remain unchanged.

Targeted negative test checks input isolation, output seed/demand separation, and subsequent tick retention. TEST_ADDED_NOT_RUN; CODE_UNVERIFIED. No local Godot runtime or CI was used. Performance gain NOT MEASURED and likely small; this is not evidence that late-tick growth is fixed.

Next: bounded same-seed early/late N150 market copy and Head phase measurements, inspect market sizes; verify test and exact N9/N39/N38/BT/RNG parity at a coordinated checkpoint. Do not duplicate Astra commits 99ab25e9/1676db61. No other owner files touched.
