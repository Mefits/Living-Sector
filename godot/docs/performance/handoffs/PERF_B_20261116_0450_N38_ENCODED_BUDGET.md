# PERF B — N38 exact encoded-byte budget (16 Nov 2026, 04:50 MSK)

CODE COMMIT: `028552e4d5e4904fe2ecb99a000c754fbe9dceb0`
TEST COMMIT: `5bb6199168cb02ef9796470a328ba67a78be2eba`

Files:
- `godot/scripts/sim/save_state.gd`: single N38 envelope encoder reused by real save path; `encoded_checkpoint_bytes` and `encoded_checkpoint_budget` report UTF-8 encoded bytes, limit and headroom. No schema, atomic .pending/.bak, f64 or limit changes.
- `godot/tests/p2_perf_b_n38_encoded_budget.gd`: targeted positive/negative regression on UTF-8, SHA envelope, final newline, oversized payload, unchanged input.

TEST EXECUTED: NOT RUN (Godot runtime unavailable in this execution).
Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
Benefit: measurable byte budget API, **not** a measured save-size reduction or runtime speedup. No real N38 checkpoint-size sample measured yet.

NEXT: Run targeted headless test, then feed a real N39/N9 checkpoint to `encoded_checkpoint_budget`, record encoded bytes/receipt count and compare growth vs 16 MiB across checkpoint intervals. Do not activate N38 vNext segmented format without old-format restore/negative integrity tests and agreed checkpoint.
