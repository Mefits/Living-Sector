# Late-tick growth investigation

owner: root / direct user request 2026-11-16
status: RELEASED
base: 1c8b4b2bf7411505876927d730d390ebb3ca10e8
scope: credit_ledger.gd profiling; n39_native_world_production.gd measured growing call sites; n158_production_runtime.gd only if profiling identifies a growing read path; new p2_late_growth_* tests and own handoff.

Do not edit these central files concurrently. No main.gd, UI, interpolation, balance, AI cadence or N38 format changes. Inspect the existing 2600-tick Actions probe first. Short replay windows from genuine early/late checkpoints, exact state and negative tests before publishing changes. Remains in PR262, no merge to base.

Continuation: owned N149 and N21 staging implemented; read-only balance queries avoid exporting history. N158 change limited to restoring the original staffing-only colony work_shift (tick/workers). Owned paid-dock and legacy tamper guards pass locally on 4.6.3. Rebased onto 863cb906, retaining C occupancy and B 1024 partitions. Bounded early/late A/B currently running; do not change these call sites until the final handoff.


2026-11-17: follow-up on b98f5a8fbd3f1eff606e3ff855750cd5af8c18f9. User explicitly requested code-only continuation; heavy checks and Actions delegated to others. Weak parent ownership, N152 no-change owned staging, N91 funding projection and ship-only writes implemented. Current code not executed. See ../LATE_GROWTH_CODE_FOLLOWUP_20261117_RU.md. Earlier run-in-progress notes above are historical, not a current verification claim.
