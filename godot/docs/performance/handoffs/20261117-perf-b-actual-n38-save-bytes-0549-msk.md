# PERF B — actual N38 save buffer bytes (17.11.2026)

- Code: d475e14ab09f3cfb489599cee5becb141d4ee4b9 — `godot/scripts/sim/save_state.gd`
- Test: 88e3bd68c7c9dc7191cbd33a4f22b6322c99f48f — `godot/tests/p2_perf_b_n38_actual_save_bytes_20261117.gd`
- Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no new CI, no measured speedup.
- Change: expose `SaveState.last_save_encoded_bytes()`, updated from the actual already-created UTF-8 buffer used by `save_runner()` and 16 MiB limit check. No second JSON traversal, no archive migration, no change to .pending/.bak, f64, checksum or receipts. Value -1 before first encoding; after attempt reports exact encoded size, including over-limit attempts. Invalid preflight leaves previous value unchanged.
- Negative test: invalid/unstarted runner must not be snapshotted or change byte metric; diagnostic encoded budget matches UTF-8 buffer including Unicode.
- Limitation: this exposes the size only at an actual N38 save attempt, not automatically at ticks 100/300/600/900. No proof N38 is a per-paid-tick hotpath; no retention fix claimed.
- Next: E/runner owner can sample this diagnostic at existing N38 checkpoint cadence (without adding serialization). Compare N9 receipt counts and actual N38 bytes at 100/300/600/900, and only then consider a bounded archive strategy. Run targeted regression and real save/restart parity at next shared checkpoint. Do not duplicate 99ab25e9 or 1676db61.
