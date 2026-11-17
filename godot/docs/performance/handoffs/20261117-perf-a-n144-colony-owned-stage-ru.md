# PERF A handoff — 2026-11-17 N144 colony approval owned stage

- CODE: 37ad73ea058c9af3288ad79242f07af1153607bb
- TEST: 71b4e1fbb5d35f4af037e3defcf329c0f152761a
- Files: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n144_colony_owned_stage.gd
- Change: N144 apply_native_n144_found_colony no longer deep-copies the entire World at L2128; root is shallow-copied and construction_sites, construction_receipts, research_directors are independently deep-copied before mutation. Existing Schema.validate, Schema.accounts, ledger snapshot, per-faction and allowed-domain checks remain unchanged.
- Evidence: source-level write-set is limited to those three domains. Full-copy oracle and rejection/alias negative fixture added.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. No measured CPU benefit; this may be an infrequent path, not the dominant late-tick bottleneck. No CI started.
- Next: run targeted N144 test in coordinated checkpoint; compare actual N144 paid cadence/copy-site cost against L196 and remaining N39 publish copies. Require same-seed N9/N39/N38/BT/RNG/contract/cargo parity before claiming improvement.
- Do not repeat 99ab25e9, 1676db61, or the already changed L196 stage. No changes to C/D/E domains.
