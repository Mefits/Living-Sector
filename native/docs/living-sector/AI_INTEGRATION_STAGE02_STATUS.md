# AI integration stage 02 — source handoff (not compiled)

Base: `Living-Sector-Galaxy-0.2-AI-Stage01-SOURCE.zip`.

## Real changes

- New `strategy/planning/baseline.rs`: `BaselineAdapter` implements the shared `Planner` trait by **projecting an action chosen by the existing Genesis director**, not by inventing new priorities.
- `native_first_actions` converts the coordinator's **already native-validated** immediately-ready `deliver`/`build` alternatives to one-step `ActionSpec` entries. Prices represent *first payment only*, not completion of entire construction or supply chains. Not all native actions are covered: research, colony, production and external market permissions remain out of scope.
- `native_decision_shadow` captures real faction ECS/contract state and applies common plan validation. Returns `ShadowTrace` with `mode="diagnostic_only"`; never dispatches, never writes to markets, contracts, or save files.
- Coordinator computes shadow only with opt-in `LIVING_SECTOR_PLANNER_SHADOW=1`; default mode keeps the original logic and avoids the extra ECS scans. New optional `head.planning_shadow` API field is diagnostic only.
- Added Rust unit tests for the baseline contract, absent native actions, insufficient treasury, and absence of shadow side effects. Updated one manually constructed `HeadDecision` test fixture.

## Important limitations

- **No rustc/cargo in the current environment**; network access to obtain a toolchain is unavailable. Changes are **NOT COMPILED and NOT RUNTIME TESTED**.
- Previous `genesis-server-linux` and `Genesis-Server.exe` files are **unchanged old Galaxy 0.2 binaries**. They do not include the new code; running them tests only the old game.
- No HTN, Telic/GOAP, Beam or Cranium runtime adapter is integrated. Source code of the old benchmark is preserved separately for the next stage.
- There is no planner-to-native dispatcher or durable plan/receipt lifecycle yet. Do not use or describe shadow proposals as executed work.

## Verification available now

- `node --test observer/strategy-model.test.mjs`: 13/13 passed on the current source tree (old Observer model).
- Source-level inspection of integration calls and patch against Stage 01. These are not a substitute for Rust compilation.

## First required build gate

On a machine with Rust/Cargo, launch `VERIFY-AI-STAGE.cmd` (Windows) or `bash scripts/verify-ai-stage.sh` (Linux). It runs `cargo check` and focused `cargo test` with `--locked` and saves logs in `ai-build-validation/`. On failure, hand back the ZIP plus logs; do not change dependencies or use stale binaries to claim success.

If checks pass, next step is **durable active-plan state + receipt mapping and actual HTN adapter on the same native action catalogue**. Before allowing the plan to issue any orders, implement and test live validation, idempotency, and save/restore. Keep utility/personality as selector; add GOAP and Beam as independent and later hybrid alternatives.
