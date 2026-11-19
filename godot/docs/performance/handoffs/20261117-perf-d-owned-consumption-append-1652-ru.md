# PERF D — N150 record_consumption owned append, 17.11.2026

- CODE: e027d600c53247005ea69c3adf1d5885f82338af
- TEST: caafebee6fe7e4512b093b47687714f5efcdca72
- Source: godot/scripts/sim/phase1/n150_native_full_market_tick.gd
- Test: godot/tests/p2_perf_d_n150_record_consumption_owned_append_20261117.gd
- Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no Godot runtime or benchmark executed.
- Change: record_consumption already deep-copies flow. It now appends to that owned commodity Array instead of deep-copying the same growing history again. Malformed non-array commodity history returns explicit error. Original input remains detached, no changed valid-input outputs or cadence.
- Scope: this is the consumption ingestion path, not proof that the measured markets phase degradation was resolved. No claimed CPU gain.
- Next: run targeted test and source parity, measure per-market MarketHistory duplicate cost and paid tick early/late same seed. Check exact N9/N39/N38/BT/RNG/contracts/cargo before accepting broader changes.
- No edits to N9, N39, N152, N158, ships or UI; no merge/force push; no CI triggered.
