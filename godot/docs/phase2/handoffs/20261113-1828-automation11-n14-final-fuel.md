# P2 handoff — N14 final-leg fuel, 13.11 18:28 MSK

- Branch: `integration/godot-phase2-unified-20261113`, PR #249.
- Code commits: `826e19ceaa862204306f4bbc2abc69fa2ea379b7`, `36db50d66eab084f6a5feb6b454285b8e2ede86d`.
- Gate 2: `ship_transit.gd` no longer lets a ship arrive for free when its remaining distance is within one movement step but it lacks that step's fuel.
- Last movement step now deducts native class fuel consumption before arrival; a ship with insufficient fuel stays in transit and returns `out_of_fuel`.
- The existing arrival-threshold branch remains a zero-distance snap, not an extra movement step.
- New `p2_ship_transit_fuel_check.gd` covers insufficient fuel, retry with fuel, arrival and exact one-step deduction.
- One N39 World/Clock/Ledger and N14 ship phase remain authoritative; no new wallet, runner, cargo or save format.
- Verification: static source review only. Godot 4.7.2 unavailable here; **WIRED_CODE_UNVERIFIED**.
- No GitHub Actions dispatched; no Windows ZIP generated.
- Lease `20261113-1818-automation11-ship-fuel-arrival.json` RELEASED. Files free.
- Next: run local Godot parser + new last-leg test + `p2_unified_ship_phase_check.gd`; then check a real arrival/docking UI and save/reload with the current N39 snapshot. Native Rust 0.6.7 fuel policy still needs explicit side-by-side acceptance before declaring parity.
