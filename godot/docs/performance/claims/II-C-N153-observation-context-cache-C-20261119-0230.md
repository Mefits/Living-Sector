# II-C N153 observation/context cache
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 02:30 MSK
BASE SHA: dbdba30573162de3b6a7b9784781651abd4d924a (previous C checkpoint; current branch HEAD read from PR #262)
ASTRA: II-C ship/contract/dock/route caches; repeated N153 offer x bidder observation materialization.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_observation_context_oracle.gd
GOAL: reuse immutable proposal-local source quote observation and system context per bidder/source/price while preserving source-order gates, mutable alias boundaries and N153 decision parity. Positive/negative oracle: changed price, source, ship location, memory, resolver, independent proposals.
TEST: NOT_RUN
