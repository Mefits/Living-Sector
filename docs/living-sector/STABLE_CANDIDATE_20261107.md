# Living Sector — stable integration candidate, 2026-11-07

This branch is an **isolated candidate**, not a merge into `main`.

## Implemented and preserved
- Unified Genesis S1–S7, F1–F4, six original systems and 36 bodies, native Observer V5 with modular station-kit assets, payments/liquidity and construction orbit fixes (PR #38).
- Astra A1 station administrator and A2 durable orders (PR #41, #43), including native contract and builder execution.
- Native Observer station economy inspector (PR #40 via integration PR #44).
- Observer read-only strategy sections for `/api/strategy.stations[]` and `orders[]` (no invented explanations), plus V5.1 standalone design reference in `observer/reference/`.
- Conservative baseline adjustments: seed population Genesis 50 / Pirates 24 / Ceti 30; process_ice now outputs 10 water + 5 fuel from 8 ice; existing paid wage policy remains 1 CR/shift.

## Balance limits
The separate accepted `observer/reference/balance-presets/base-0.3.json` reflects **Balance Lab units per person per tick**, whereas native `PopEconomy.consumption` currently represents per-1000-pop **per consumption cycle** (5 base ticks), and the game uses native facility cadence and workforce constraints. It is NOT executable Rust configuration.
Therefore we have deliberately NOT copied food=0.12 / water=0.13 directly into `consumption` fields, nor assumed prototype construction costs equal native F3/F4 costs. Doing so without a tested unit conversion would break survival and invalidate the accounting. The accepted baseline remains available for later native calibration.

## Deferred after audit
- PR #39: Survival/mining pilot is WIP; author explicitly marked no executed Rust tests or Windows build, overlaps A2 ship/facility code. Not silently merged.
- PR #42: 2× orbital scaling, new SQLite migration and observer camera follow is WIP; no native Windows build, intersects A2 persistence/snapshot and station inspector. Not silently merged.
- Old draft PRs #24–35 are ancestors or parallel alternatives; do not replay on top of unified integration.

## Validation
Check GitHub Actions for this exact candidate SHA. Do not label a portable artifact stable unless Windows release build and native smoke pass. A short smoke does **not** prove economically self-sustaining colonies or 1000-tick balance.
