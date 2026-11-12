# N107 — Native station administrator

Source `native/crates/sim_core/src/strategy/station.rs` frozen 0.6.7. Ports local 3/5 labor pool, occupied workers, essential commodity urgency, full-team allocation, owner-funded wage + 10% processing overhead, previous assignment retention, station needs and feedback. Recipe viability and precursor resolution are supplied by native recipes/production_chain; no fabricated production, wages or stock. Snapshot adapter must preserve owner/faction/location identity and actual paid shifts. Pure data projection, CODE_UNVERIFIED.
