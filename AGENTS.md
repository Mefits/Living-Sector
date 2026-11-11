# AGENTS — Living Sector Godot (coordination)

**For all coding agents and concurrent chats:** read and obey the shared, authoritative [overnight queue](godot/docs/NIGHT_SHIFT_QUEUE_RU.md), [claim protocol](godot/docs/nightshift/CLAIM_PROTOCOL_RU.md), [run log](godot/docs/NIGHT_SHIFT_LOG_RU.md), and [migration tracker](godot/docs/MIGRATION_TRACKER_RU.md).

**CRITICAL:** TWO AGENTS MAY BE CODING CONCURRENTLY. BEFORE doing research, editing, planning implementation, or committing working code, reserve one free `N1`…`N8` block by a GitHub **create_file** call for `godot/docs/nightshift/claims/Nx.json` on the common branch `feature/godot-nightshift-20261112`. The content must contain `status: IN_PROGRESS`, owner, unique run_id, timestamp and selected work branch. **Do not create in your own isolated branch.** If it already exists, skip the block and choose another. Immediately reflect claim in common queue and log, **then** start the actual work on your own branch and PR. Never overwrite or remove another agent's claim. Do not assume a stale table means the claim path is free.

**Keep real Rust gameplay as the behavioral specification.** The Godot port uses built-ins first, external addons only after version/license/Windows validation. No paid GitHub Actions, long Rust builds, fake simulation results, automatic merge/force-push or changes to frozen Rust branch. Update statuses only with evidence. Every report must contain **Текущее состояние: P0 X/9, P1 X/9, P2 X/11, overall X/100** and what remains unverified.

This root file is a coordination entrypoint. The full [Godot AGENTS](godot/AGENTS.md) gives the compact implementation-specific rules.
