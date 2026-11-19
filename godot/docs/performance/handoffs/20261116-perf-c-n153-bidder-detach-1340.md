# PERF C handoff — 2026-11-16 13:40 MSK — N153 bidder alias boundary

- Branch / draft PR: `integration/perf-astra-5-workers-20261116` / #262.
- CODE SHA: `df24f1de239d26649248331397df4077b84865ed`.
- TEST SHA: `3f1a60f8945c6cc92ce18a6adfa0e7862ecfa098`.
- Files: `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`, `godot/tests/p2_perf_c_n153_bidder_detach_oracle.gd`.
- Fix: `legs()` previously returned the proposal-owned cached Dictionary and nested arrays directly. Mutating a bidder's `steps`, `inbound`, or `outbound` could alter later bids and fuel geometry. Now only detached flat scalar rows and location arrays escape; cache retains its authoritative copy. Error dictionaries are detached too.
- Oracle: repeated bidder mutation, nested row mutation, independent bidder, changed-position fresh proposal, and negative endpoint.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (no Godot execution in this run). No measured speedup; small allocation overhead is expected for safety. No Rust cadence, balance, contracts, cargo, or paid receipt logic changed.
- NEXT: run targeted oracle plus existing `p2_perf_c_n153_offer_route_index_oracle.gd`, then same-seed paid-contract decisions/fuel/cargo parity and N38 restart checkpoint; profile N153 before further copy reductions.
