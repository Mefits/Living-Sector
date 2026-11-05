> **CURRENT GENESIS ENTRYPOINT (2026-11-05):** Read [docs/living-sector/ASTRA_START_HERE.md](docs/living-sector/ASTRA_START_HERE.md) first. For the current headless 2D Genesis, use branch `feature/genesis-faction-economy` (draft PR #8), based on `feature/genesis-core-reuse` (draft PR #7). `main` and `living-sector-dev` are **not** the current Genesis implementation. The polished Observer 0.14 and its sprites are, at this stage, in a separate Windows ZIP, **not committed as UI sources in this branch**. Do not assume they are in GitHub. Do not merge the PRs without the owner's instruction.

# Working rules for AI contributors — Living Sector

This repository is a **fork of [Kalcode/spaceprojectsim](https://github.com/Kalcode/spaceprojectsim)**. Our current project name is **Living Sector**. Work with the actual Rust/Bevy code; an older Godot prototype is *historical concept material*, **not** this repository's application architecture.

## Read before changing anything

1. [docs/living-sector/README.md](docs/living-sector/README.md) — entry point and document status.
2. [docs/living-sector/STATUS.md](docs/living-sector/STATUS.md) — what has *actually* been inspected or tested.
3. [docs/living-sector/VISION.md](docs/living-sector/VISION.md) — long-term vision.
4. [docs/living-sector/DESIGN.md](docs/living-sector/DESIGN.md) — agreed directions versus open choices.
5. [docs/living-sector/ARCHITECTURE.md](docs/living-sector/ARCHITECTURE.md) and [ROADMAP.md](docs/living-sector/ROADMAP.md).
6. Original [CLAUDE.md](CLAUDE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [CONTRIBUTING.md](CONTRIBUTING.md) and current source files: the upstream documents can lag behind code.

## Rules

- Do not mistake inspiration, a discussion example, an engineering proposal, and an implemented feature.
- **Do not replace the existing Rust/Bevy simulator with Godot/C#/TypeScript.** The possibility of a future personal-scale mode does not authorize a rewrite.
- Do not start implementing features or updating upstream code without a concrete task.
- Preserve compatibility with the original fork when reasonable; prefer isolated modules, clear interfaces, and small changes.
- Main branch should remain close to upstream. For **current Genesis work**, base new branches on `feature/genesis-faction-economy` until the owner chooses a different integration baseline; older work may still branch from `living-sector-dev`. Never force-push, rewrite history or merge open draft PRs without instruction.
- Preserve the original MIT LICENSE and attribution. Avoid secrets, paid services, telemetry, unrequested publishing or unrelated refactors.
- Prefer the smallest relevant Rust check, e.g. `cargo check -p sim_core` / `cargo test -p sim_core`. Run full checks for integration changes when a tool environment is available.
- Minimize AI/Codex context cost: limit inspected files and log output to the affected modules. Do not claim tests passed if you did not run them.
- Keep simulation, presentation, persistence, and game decisions distinct. Confirm critical state transitions are applied once.
- For each substantive task, record changed files, checks performed / not performed, current risks and next action in [STATUS.md](docs/living-sector/STATUS.md). Record only explicitly agreed game rules in DESIGN.md.
- Reply in Russian by default, compactly, without repeatedly asking the owner to restate documented goals.
