# Astra II-C D — deterministic event snapshot reuse
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
TIME: 2026-11-19 12:40 MSK
BASE EVENT BLOB: b6b61ec441e8c7b2bde32c3e41ac3257286a5faa
TASK: D event queue repeated sorting of unchanged pending roster; bounded ordered references invalidated on every schedule/cancel/take_due/restore.
FILES: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_snapshot_reuse.gd
ORACLE: compare snapshot and due ordering against canonical independent comparator; mutation and failed restore, payload detachment.
RISK: never cache exposed mutable snapshot; only internal sorted borrowed rows, fresh deep copy for caller.

CODE SHA: a3f79f81f156b4164d717e2d9c3800b29b401f65
TEST SHA: 9c34c2ac32147056000fa003b187699c57db2c98
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
IMPLEMENTED: event_queue.gd snapshot() reuses only internally borrowed canonical sorted references. schedule/cancel/nonempty take_due/successful restore invalidate; failed restore retains existing state. Public snapshots still deep-copy payloads. No change to paid dispatch comparator or serialization schema.
ORACLE: independent comparator over 96 events; repeated snapshots, schedule, cancel, take_due, failed/successful restore, payload detachment and full drain.
RISK: no Godot runtime executed; repeated snapshot sort reduction requires same-seed profiling to quantify, and snapshots may be infrequent in normal paid ticks.
NEXT ASTRA II-C D: Head/N121 multi-faction facility/contract scans; find owner call boundary and implement capture-local index with malformed-market-owner negative oracle.
