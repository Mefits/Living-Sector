# PERF B — N38 exact UTF-8 write buffer (17.11.2026)

- Code: 633a626d58772e11933a382c68ae1dc43779be8c
- Negative regression: 94c2421921687774a559b3bc1db2843f94d6c825
- Files: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_utf8_buffer_exact_20261117.gd
- Change: N38 save_runner previously measured encoded.to_utf8_buffer().size() then called store_string(encoded), which re-encodes the entire growing checkpoint. Now it measures once and writes that same PackedByteArray via store_buffer. Existing envelope, SHA, f64 tags, .pending/.bak rotation, validation, and 16 MiB limit are unchanged.
- Targeted negative regression: Cyrillic/Unicode exact disk bytes, UTF-8 size, successful authenticated decode, and SHA-covered payload tampering rejection.
- Execution: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN (no Godot runtime executed). No measured speedup claimed. This optimizes explicit N38 save cost, not proof of paid-tick growth.
- Baseline: 17 Nov HEAD CI #43972442164 PASS 500 ticks, worker+N38, same-seed 160 ticks exact snapshots 5/5. This new patch is not included in that acceptance.
- Do not duplicate 99ab25e9 N9 WeakRef or 1676db61 N158 projections.
- Next: use existing paid-tick profiles to establish N9 receipt growth and snapshot call cost; compare N38 encoded bytes at tick100/300/600/900 and check headroom against 16 MiB. Run targeted test and one bounded combined checkpoint before acceptance; avoid 900/2600 soak in this run.
