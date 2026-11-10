# Galaxy 0.3 — Windows build input

**One archive. One upload. An automatic GitHub Actions build.**

1. Download `LS-GALAXY-03-CI-INPUT.zip` from the ChatGPT conversation.
2. On this branch, open `ci-input/` and use **Add file → Upload files**.
3. Upload the ZIP **without unpacking it**, commit it to **this build branch** (not `main`).
4. A push to `ci-input/*.zip` starts the workflow **Galaxy 0.3 - Windows AI build**.
5. If Rust compiles, get the `Living-Sector-Galaxy-0.3-Windows` artifact from the run's Summary page.

The input ZIP contains `LS-AI-BLOCK-IV-SOURCES.zip`, `Living-Sector-Art-Catalog-v0.4.zip`, and the agreed `Living-Sector-Visual-Mapping-v0.1.json`.

The workflow builds `genesis_server.exe` fresh from blocks I–IV on Windows and packages `START-GALAXY.cmd`, `observer/`, and `priv/galaxy/data`. It enables the `hybrid` planner and keeps its save separate from Galaxy 0.2.

**Important:** Some SVGs are distributed as art previews only. This build step does not automatically integrate every SVG into the live map renderer. The source changes have not previously been compiled and can fail. If the build fails, send the GitHub Actions log so the error can be fixed.

Branch `build/galaxy-03-ai-actions-20261110` is intentionally isolated; do not merge it into stable/main without review.
