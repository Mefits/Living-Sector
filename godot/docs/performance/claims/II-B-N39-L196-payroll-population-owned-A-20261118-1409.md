# Astra II-B · N39 L196 payroll population ownership

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
DATE: 2026-11-18 14:09 Europe/Moscow
BASE HEAD: e9b03f1ac5377c4ef308883e2d75c786183e9980
TASK: Astra II-B L196 real paid N156 repair: replace unconditional full population deep copy with scoped owned household rows while preserving payroll assignment, blocked repair, rollback, Schema/N9 oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_l196_payroll_population_rows.gd
EXPECTED CHECK: same-seed full-copy oracle, paid and blocked payroll, multiple candidate factions/locations, nested alias isolation, full Schema accounts, no CI.

CODE SHA: 563d1a6f3c058d222125e78799bce1caf2ee1e60
TEST SHA: 8dcb81cb8803ac99870e937057d5283c08f734c7
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: n39_native_world_production.gd run_tick N156/N130 lifecycle payroll population stage.
CHANGE: L196 no longer deep-copies all households when repairs exist. It computes a union of candidate employers' faction/location pairs before any Payroll.pay_shift, shallow-copies the populations registry, and deep-detaches every eligible household (including those whose worker capacity/wealth may change between sequential paid repairs). All unrelated households remain read-only. Missing repair employer fails before any payment. Full Schema.validate and N9 account reconciliation remain unchanged. N130 and existing facility ownership unchanged.
REGRESSION: multi-employer/multi-location paid wages, nested wage history, same-location foreign faction, same-faction remote colony, invalid employer, rejected-stage rollback and explicit shallow alias negative; full deep-copy oracle. Ownership-model test, not production execution.
NEXT ASTRA II-B: inspect L129 deep World snapshot caller duplication in paid ships/dock phase and agree caller API with C; verify exact N9/N39/N38/BT/RNG/cargo parity before adopting measured speedup.
