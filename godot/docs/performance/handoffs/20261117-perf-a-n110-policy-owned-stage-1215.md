# PERF A · N109/N110 policy write stage · 17.11.2026

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

Code: `8a45805d95522819d9a519ab98e88696a4fe7737` (`godot/scripts/sim/phase1/n39_native_world_production.gd`). Replaced `L2987` full World deep-copy with shallow root and deep copies of only three optional policy write maps. Source governance still reads the canonical facilities/markets/research_directors and still performs full Schema.validate and N9 accounts parity before publish. Absent legacy maps are created only in stage; malformed map rejection preserved. No balance or ledger changes.

Test: `5b957ea7dffd9228a1d0be1032d5829937aeecb3` (`godot/tests/p2_perf_a_n110_policy_owned_stage.gd`). Full-copy oracle equality, rejected-stage isolation, missing legacy map, malformed map and negative nested mutable-alias fixture. Fixture tests copy ownership, not the production method directly.

Status: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No CPU benefit or paid-tick speedup measured; N110 player policy is likely infrequent and should not be counted as the main late-tick bottleneck. No CI triggered. No edits to B/C/D/E domains, no merges.

Next: inspect remaining `L2671` N141 construction labor stage and its nested N151 establishment mutation contract before replacing full World copy. Require exact paid/blocked/materialized and N9/N39/N38 parity, plus bounded early/late measurement. Existing L196 and Astra N9/N158 fixes must not be repeated.
