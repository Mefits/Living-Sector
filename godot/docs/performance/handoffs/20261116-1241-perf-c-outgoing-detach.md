# PERF C handoff — 2026-11-16 12:41 MSK

- Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262. No other branch/PR touched.
- CODE COMMIT: `24e6b8d63dab9740c8d6174de2306a95b0a1ae31`
- TEST COMMIT: `db1b4f8845a33422416f75c3a1ce94696bcdd68d`
- Files: `godot/scripts/sim/route_graph.gd`, `godot/tests/p2_perf_c_outgoing_detach_oracle.gd`.
- N4 `outgoing()` now detaches its flat edge row dictionaries and outer array without recursive `duplicate(true)`. Graph loader constructs edge dictionaries containing only `to` String, `distance` float and `system_id` String; caller writes cannot mutate internal graph. No route cost, graph order, fuel, paid contract, or tick behavior changed.
- Targeted oracle: sorted edge order, scalar data, returned outer and inner mutation isolation, path/snapshot unchanged, absent node, failed load rollback, successful reload.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. Reviewed actual GDScript signatures, preload path and edge shape. No local Godot test or Windows performance measurement. No Actions triggered.
- WHY: avoid recursive container-copy overhead in repeated N4 adjacency reads while retaining owned result boundaries. Speedup is unmeasured; production benefit depends on outgoing() call frequency.
- NEXT: run targeted oracle plus existing N4 cache oracle, N153 paid-contract replay, N38 restart and benchmark route/fleet calls. If no measurable gain, revert optimization. Do not treat this as FPS fix.
