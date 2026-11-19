# PERF C · N84 colony dock lookup · 17.11.2026

CODE COMMIT: bd648ded05aac567d96eed3bb4d030f3098c71c9
TEST COMMIT: 42b280a0bc7c98b1f7dbf7e8757b0d244158d155

## Actual hotpath
`unified_ship_ai_execution.gd::_real_contract_dock` is called from N84 Dock / DeliverCargo / DeliverPassengers and scanned every `construction_sites` entry even for construction contracts whose `colony_site_id` is authoritative and required by the original predicate. The construction branch now probes the named site directly. Passenger scan remains unchanged, as do market station precedence, source N151 receipt verification, faction/location checks and abandoned guard. Complexity for construction-site lookup is O(1) instead of O(number of historical sites), excluding ordinary dictionary lookup and proof validation. This is source-level improvement, **not a measured phase speedup**.

## Regression
`godot/tests/p2_perf_c_n84_colony_dock_site_oracle_20261117.gd`: independent legacy full scan vs new path with 2000 distinct sites, valid paid-contract metadata, invalid proof, abandoned dock, stale site, wrong faction/location, passenger original tie-break, station priority; checks no mutation of World. Contract/cargo/fuel apply is unchanged by this read-only lookup.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime or same-seed CPU metrics in this shift. No CI launched. Risk: regression still needs actual Godot parser/execution and full N38/BT/RNG/contract parity checkpoint.

## Next
Measure `_real_contract_dock` call count/time by contract kind and construction_sites size at paid ticks 100/600/900; if rare, prioritize N84 Travel and N153 proposal scans instead. Use one bounded same-seed checkpoint and do not repeat 99ab25e9/1676db61. No N39/N9/N158 changes.
