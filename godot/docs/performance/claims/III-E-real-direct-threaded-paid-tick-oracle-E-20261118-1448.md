# Astra III/E — real direct/threaded paid-tick parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 14:48 Europe/Moscow
BASE_SHA: 8688a48d9a67498292fa04e7d23f433cf5d2ad81
ASTRA: E bounded benchmarking protocol; direct-vs-worker same-seed exact checkpoint/N38 parity and per-paid-tick elapsed wall attribution.

CODE SHA: 853887a92bbe8f422caff5a482cd6d47f2c561bb; 1d29d0378c66a5d84b3cc7af26fda415933dd4b5
TEST SHA: c4bcb4adc655c1f2fec2ec548195a4758d611aa5; c282cc9a78bf3d18efca379bd5ae8827ca3a91fd; 66962dd066831fb84b973d66efd460994b21cb7e; 722cf50661411ee903784d01edaaf29c62de6ffd; f5817dd97624892789be1c2eb71bd9839e28cee6
FILES:
- godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd
- godot/tests/p2_perf_e_real_direct_threaded_oracle.gd

RESULT: Added executable 100 real paid-tick same-seed direct N158 vs threaded owner harness, exact detached checkpoint comparisons at ticks 1/20/60/100, real N38-style restore boundary at tick100, 100-sample bounded per-paid-tick direct advance vs worker advance/projection/request elapsed comparison, fail-closed source-clock and completeness guards. Positive and negative oracle fixtures reject cargo/RNG/receipts/tick mismatches, missing checkpoint, and multi-tick timing. Does not modify authoritative World/N9/BT/RNG, production worker/UI or source cadence. No speedup claim.

TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Godot execution unavailable in this run; no GitHub Actions launched.
RISKS: Runtime checkpoint normalization and threaded restart may produce parity differences; require real headless execution before acceptance. Elapsed wall time is not CPU time.
NEXT ASTRA E: Extend same-seed acceptance with source tick 100/300/600/900 size-growth and late-phase bounded windows; collect actual N38/BT/RNG restart and phase measurements at one agreed test checkpoint.
