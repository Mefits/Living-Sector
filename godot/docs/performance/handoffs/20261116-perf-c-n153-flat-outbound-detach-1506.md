# C · N153 flat outbound geometry detachment · 2026-11-16 15:06 MSK

- Code commit: `3c900ca9d78bfbefdc47d50b86242d292cebb2f4`.
- Test commit: `65a2d6b3b773f6a2760d0ad3154072281cd88366`.
- Files: `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`, `godot/tests/p2_perf_c_n153_flat_outbound_copy_oracle.gd`.
- Change: replace outbound `Array.duplicate(true)` recursive copy with the same bounded per-row shallow copy already used to detach bidder results. Rows produced by `_geometry_steps` are flat scalar dictionaries (bool/float). Array and every row remain separately owned; preserve inbound-first ordering and per-proposal cache scope.
- Tests: **NOT RUN / CODE_UNVERIFIED**. New oracle checks flat row isolation, missing-position sentinel, route geometry, independent bidder results, and no poisoning of cached outbound geometry. Existing `p2_perf_c_n153_bidder_detach_oracle.gd` remains applicable.
- Benefit: removes recursive traversal on each outbound cache hit. **Not measured**; no claimed FPS/TPS improvement. No changes to contracts, wallets, fuel/cargo rules, N39/N9/N158/N38.
- Next code step: compare N153 paid-contract bidder decisions and fuel/cargo with uncached oracle, then bounded Godot checkpoint with N38 restart; measure N153 phase cost before further cache work.
