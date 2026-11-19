# Astra II-B · N39 N97/N83 service/trade owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 12:10 MSK
BASE_SHA: 8df4e1cc8e6607efa76a4b2727623cecbd11cf1b
ASTRA: II-B bounded owned write sets / N39 deep:L129/L196; paid ship service and free trade publication.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n97_n83_owned_publication.gd
SCOPE: replace full proposed World publication with row-owned detached ship/market/facility/body/receipt domains, preserve full schema and N9, negative alias/rollback/oracle; no change to C source stages.
TEST: NOT_RUN

CODE_SHA: 98797af2ffb4fa983584b1e7eb264630d63125e3
CODE_GUARD_SHA: dd733a1cbbfbae874427ed8d335b94cbbf41ec7f
TEST_SHA: e78fddb08ac21f2aa10e30a85c4f27ade9b2217b
TEST: NOT_RUN
CODE: _n97_n83_owned_physical_publication; apply_native_n97_ship_service; apply_native_n83_free_trade.
EFFECT: after original full Schema/N9/receipt checks, construct a shallow World header and detached changed ship/facility/market/body rows and new receipt only; reject changed unowned rows, old receipt tampering, topology changes. Revalidate full Schema after publication before atomic World/Ledger commit. No edits to C-owned source staging.
REGRESSION: p2_perf_a_n97_n83_owned_publication.gd; refuel, mine, trade, rejected cursor, consecutive receipts, deep-copy oracle, nested aliases, negative missing/altered history and ownership, malformed rows and unrelated mutation.
RISK: CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED; source stage may still perform its own full deep copies. Must run parser, targeted regression, same-seed World/N9/BT/RNG/N38 and paid tick benchmark before claiming speedup.
NEXT: Astra II-B N39 L129 repeated snapshot caller ownership; isolate remaining actual paid-tick redundant deep copies without revisiting N121/N100 or completed N97/N83.
