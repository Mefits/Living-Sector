# II-C N153 observation/context cache
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 02:30 MSK
ASTRA: II-C ship/contract/dock/route caches, N153 repeated offer x bidder observations.
BASE: PR #262 head observed before claim; claim commit a13bff6395c205c92d893545630f4ec406404e44.
CODE SHA: 4048f2e11af5313ae637bfa9cb8e0ffb47548079; 9cd72fb4b8b7defb80da9661be8be87c16117987
TEST SHA: dce80f7d858e2e3b45dff1da883caea602dac4bb
FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_observation_context_oracle.gd
CHANGE: per-proposal memoized source price-knowledge overlay keyed ship/source/commodity/price; per-proposal system tuple keyed here/source/destination. Repeated bids reuse immutable source observations and system maps, avoiding repeated shallow copies/resolver context materialization. Cache lifetime only propose(), never World/N38. N153 selector reads both views without writing. Real route, cargo, payment, faction and BT gates unchanged.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Targeted oracle compares old shallow-overlay semantics, repeated offers, changed price, changed origin, missing system, new proposal/World, here==source. No Actions per user. Full paid-tick N9/N38/BT/cargo/route parity remains unverified.
RISK: read-only selector assumption; cache key arrays and contextual map behavior require Godot parser and runtime oracle. No claim of speedup without paid-tick measurement.
NEXT ASTRA II-C: dock occupancy index and N84/N153 real paid-tick 24/100/500 ship replay, cached-vs-uncached exact BT/cargo/fuel/route negatives.
