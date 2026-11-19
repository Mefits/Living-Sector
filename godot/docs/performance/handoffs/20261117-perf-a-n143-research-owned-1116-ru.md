# PERF A — N143 research paid stage (17.11.2026, 11:16 MSK)

- Branch: `integration/perf-astra-5-workers-20261116`, PR #262. No merge/force push.
- CODE SHA: `cbde539c0a65368f176241b236aaceadce00962b`; `godot/scripts/sim/phase1/n39_native_world_production.gd`.
- TEST SHA: `784715d3472641ef0007b13c81ad19720a345aea`; `godot/tests/p2_perf_a_n143_research_owned_stage.gd`.
- Replaced N143 `_copy_world("L3098", true)` with detached root plus exactly nine deep-copied write domains: research_directors, research, research_receipts, research_mandates, faction_charters, faction_treasuries, facilities, populations, markets. Paid research mutates these domains; untouched ships/contracts/construction no longer copied on this stage. Full Schema.validate, Schema.accounts, N9 fork/receipt/wallet parity and atomic publish unchanged.
- Regression fixture compares owned stage with full-copy oracle, checks rollback isolation and negative shallow nested alias. It is a stage ownership test, **not** a production N143 integration test.
- TEST: NOT RUN; CODE_UNVERIFIED. No Godot runtime/CI executed in this iteration. No measured speedup or long-run parity claim. Earlier CI #43972442164 does not cover this commit.
- Next: targeted Godot N143 production paid/rejected/repeated-receipt test; 160 same-seed strict N9/N39/N38/BT/RNG/cargo/contract comparison, then early/late measured CPU ms/paid tick, p95, site calls/time. Inspect remaining L2671 construction labor before changing it.
