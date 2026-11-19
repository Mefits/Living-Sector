# Astra II-B — N154 shipyard paid owned rows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 06:12 MSK
BASE_SHA: 19b6c1a63911f19e0f6c2febd85ada03dc77cb7c
CODE_SHA: 7529707cd631b407a4c95801b632b8e0b7dacfec
TEST_SHA: cb47dd2a58b46146da1458451e61169eada2f613
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
ASTRA: II-B bounded owned write sets, local validators, versions & delta; N39 L129/L196
FILES:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n154_shipyard_payroll_owned.gd

IMPLEMENTED: Real _run_shipyard_modules paid N154 path now uses _n154_owned_shipyard_payroll_stage instead of deep-cloning three entire registries. Detaches producer and stock-owner facility rows, eligible faction/location households, and actual local market. Includes rejected Payroll._blocked mutation path; avoids aliases into authoritative World before N9 fork/Schema and final publication. Unrelated rows remain read-only. No change to wage, production, N9 ledger, module cadence, or Schema guard.

REGRESSION: positive old deep-registry oracle for all paid write targets; negative blocked payroll, malformed/missing owner/location/market/population, rollback and nested mutable aliases. Test staged but not executed. Full same-seed N39/N9/N38 parity and Windows profile still required.

NEXT: Astra II-B remaining deep:L129/L196 paid N39 stages; inspect construction escrow/other native write sets not yet covered and add true production-path negative/Schema oracle. Run this N154 regression and full same-seed N38 restart at morning acceptance.
