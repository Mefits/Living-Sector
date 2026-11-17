# PERF A · 2026-11-17 · N144 head-only owned stage

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

Code: `82ece8e7898a038bc7a517aa90bfe17da8b3f600` — `godot/scripts/sim/phase1/n39_native_world_production.gd`.
Test: `e186374f0779e71752d99606a66259f2487f13e6` — `godot/tests/p2_perf_a_n144_head_only_owned_stage.gd`.

Replaced N144 passenger approval's unconditional `_copy_world("L2289", true)` with a shallow root. When no paid order is posted, head-memory writes detach the research_directors map and only the owning faction director recursively; no unrelated World domain is copied. When a paid order is posted, the detached authoritative `posted["world"]` still replaces the initial root, preserving the existing source-paid proposal path and validation. No guards, Schema oracle, N9 reconciliation, receipts or balance rules were removed.

Negative test models the exact owned-stage operation against a full deep-copy oracle, verifies rejection isolation, detached incoming memory, and proves a shallow director-row copy would leak nested history. It is a structural test, not a production-path integration test.

TEST_ADDED_NOT_RUN / CODE_UNVERIFIED. No Godot runtime executed. Performance gain NOT MEASURED; N144 is likely infrequent, and this change is not evidence of fixing late-tick slowdown. No CI started. The previously passing #43972442164 predates this change.

Next: targeted Godot test, N144 authorized and head-only integration fixtures, N38 restart and same-seed exact N9/N39/BT/RNG parity. Prioritize measured remaining N39 full-copy sites L2671/L2987/L3098 and regular tick paths before further rare-event optimization. Avoid N9 WeakRef, N158 projections and previously optimized L196.
