# Galaxy 0.3 — Actions build inputs

This directory is a manual staging area for the **uncommitted Galaxy 0.2 + AI blocks I–IV** sources that were shared as ChatGPT ZIP attachments.

Upload **both ZIP files here, in the same GitHub commit** (Add file → Upload files). The Actions workflow will start automatically:

1. `LS-AI-BLOCK-IV-SOURCES.zip` — complete source snapshot (contains `Living-Sector-Galaxy-0.2/Cargo.toml` and `Cargo.lock`).
2. `Living-Sector-Art-Catalog-v0.4(1).zip` — original SVG art catalogue (the filename may contain `(1)`).

Why manual upload? The GitHub connector cannot transfer binary ChatGPT attachments directly into the repository. This branch deliberately keeps these sources away from `main` and all stable branches.

After uploading, go to **Actions → Galaxy 0.3 - Windows AI build**. If compilation succeeds, download the `Living-Sector-Galaxy-0.3-Windows` workflow artifact. It contains a portable Windows server, Galaxy game data, browser Observer, launch script, and the art catalogue. Not all SVGs are wired into the live map yet.

This branch is for the build only; **do not merge into main automatically**. It does not claim that the untested blocks I–IV compile successfully.
