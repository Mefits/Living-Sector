# Astra II-B — N39 N104 accept owned rows
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 08:12 MSK
BASE BLOB SHA: d13503a058b1b3db72ab694eafdd91f38107de5b
BACKLOG: II-B bounded owned write sets, rollback and Schema oracle; N39 L196 paid stages.
SCOPE: apply_native N104 contract acceptance: escrow/faction/facility/ship detached write-set instead of four deep domain clones.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n104_accept_owned_rows.gd.
CHECK: old deep-copy oracle equivalence, nested alias, missing row, negative rollback; full Schema and N9 preserved. TEST_NOT_RUN pending Godot.
