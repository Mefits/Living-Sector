# PERF A handoff — 2026-11-17 03:31 MSK — N135 funded contract World copy

Branch: integration/perf-astra-5-workers-20261116 (PR #262). No merge or force-push.

Code: 7f9ccf34e418a615260780d9534506f5cea6e295
Test: 211db746097130a046cf0730a69b6ce58de4bdec

Changed:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n135_owned_funded_contract.gd

N135 post_funded_contract() formerly called _copy_world("L3452", true) for each successfully staged posting. Now it shallow-copies the authoritative root, deeply detaches contract_board and escrow_balances, shallow-copies the facilities map and deeply detaches the single buyer facility row before changing credits. All Schema.validate, Schema.accounts, N9 total/receipt and atomic publication checks remain unchanged. No external proposal aliases are published.

Regression compares owned stage against full deep-copy oracle, verifies source isolation on rejected candidate, and demonstrates failure of an unsafe shallow facility-row alias.

CODE_COMMITTED / CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or CI triggered. Expected saving: one full World deep copy per successful N135 funded posting, replaced by proportional copies of board, escrow and payer row. Frequency and CPU ms improvement NOT MEASURED; this is not a proven fix for deep:L129 or late-tick degradation.

Latest checkpoint #43972442164 PASS predates this patch. No changes to N9 WeakRef, N158 projections or L196 already optimized. Next: run targeted Godot regression and same-seed early/late N135 site counts/time with full N9/N39/N38/BT/RNG/contract/cargo parity. If N135 frequency is low, prioritize another measured full write stage rather than claiming significant gain.
