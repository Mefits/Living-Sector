# Astra II-B — N39 N14 ship phase owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
DATE: 2026-11-19 13:10 MSK
BASE SHA: 4faa483bf766d0b9bdb137976b74118cdd7a7cd3
BACKLOG: II-B bounded owned write sets; real N39 paid ship-phase hot path, L129/L196 copy pressure.
CODE SHA: 665f11b7ef57ee700f4276197e8d54abd9c4f03f
TEST SHA: 0510109ba400a3c3595871952c0c75217f8066de
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n14_ship_phase_owned_publication.gd
CALLSITE: apply_ship_phase (N158 N14 ship commit); new _n14_owned_ship_phase_stage.
RESULT: replace full ships registry deep-copy per changed N14 commit with shallow registry + deep detach of changed ship rows only. Preserve frozen physical fields, complete roster, nested aliases, ship_next_token, existing full Schema.validate and N9 balances checks before authoritative World publication. No changes to cadence/BT/RNG/cargo/wallet.
NEGATIVES: missing/extra ship, malformed row, all frozen-field changes, repeated publication, nested mutable alias and rejected-stage rollback; legacy full deep-copy value oracle.
TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
RISK: Godot parser, full N158 integration, N38 restart and same-seed replay require later Windows test. Proposal generation may still deep-copy fleet in C-owned code; do not edit C files.
NEXT: Astra II-B N39 L129 repeated world_snapshot callsites in A-owned physical paid stages; find next unclaimed owned-write/Schema stage and preserve full oracle.
