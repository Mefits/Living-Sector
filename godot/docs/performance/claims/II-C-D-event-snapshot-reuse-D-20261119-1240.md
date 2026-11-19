# Astra II-C D — deterministic event snapshot reuse
STATUS: IN_PROGRESS
OWNER: D
TIME: 2026-11-19 12:40 MSK
BASE EVENT BLOB: b6b61ec441e8c7b2bde32c3e41ac3257286a5faa
TASK: D event queue repeated sorting of unchanged pending roster; bounded ordered references invalidated on every schedule/cancel/take_due/restore.
FILES: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_snapshot_reuse.gd
ORACLE: compare snapshot and due ordering against canonical independent comparator; mutation and failed restore, payload detachment.
RISK: never cache exposed mutable snapshot; only internal sorted borrowed rows, fresh deep copy for caller.
