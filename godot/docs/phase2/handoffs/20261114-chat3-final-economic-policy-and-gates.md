# Living Sector P2 · Chat3 FINAL source handoff / RC1 check

Date 2026-11-14 · shared branch `integration/godot-phase2-unified-20261113` · PR #249

## Result: feature-source work paused, ONE actual smoke triggered

This closes Chat3's final N109/N110 economic-policy input block and moves the shared migration onto one combined real Godot/Windows acceptance. This is a **RELEASE CANDIDATE FOR TESTING**, *not* SOURCE_INTEGRATION_COMPLETE and not a Godot PASS.

A single push trigger to `godot/docs/phase2/P2_CI_TRIGGER.txt` was committed as **`40bfff2a3db670fad6a908fbafa2f9b8aa8c6997`**. The existing `.github/workflows/p2-unified-godot-smoke.yml` is configured for this exact path and runs one Godot 4.7.2 editor/import, all-script compile, N158 live paid production, and N143 paid research/N38 save test. GitHub's connected commit-status APIs did **not** expose the push-run result in this session; **result UNKNOWN, not success/failure**. Workflow URL: https://github.com/Mefits/Living-Sector/actions/workflows/p2-unified-godot-smoke.yml.

## This block's source changes

- `5ae0ce3`: Original optional `Director.economic_mandates` map starts EMPTY in the one N158→N39 clean source World. No NPC player mandates auto-generated.
- `364521f`: N39 Schema validates the original kind, commodity, mode, budgets, and **real faction-owned station** before admitting an economic directive; legacy checkpoints without the map remain valid.
- `c1cdace`, `73aa79e`: original N110 economic amounts, min-stock and optional last paid tick normalize as exact JSON numbers through the existing N38/N39 shared policy guard. Inexact/fractional/future values cannot enter trusted N38 backup.
- `ce98383`: single N39 source policy control now accepts `set_economic_mandate` and `clear_economic_mandate` in addition to N109 charter and N110 research, preserving earlier actual spent/created/last_commitment when the goal key is unchanged, **no funds or contract created**. Checks faction's real market/station owner and N39 Schema.accounts immutability.
- `f653590`: N158 `request_faction_policy(faction_id, operation, policy)` routes explicit in-game user control commands through that one N39 policy method at current tick. No hidden AI override and no duplicate wallet.
- `6256e39`: source-gate N84 dock-timeout marker reconciled with the *real* released N104 ReleaseContract / PickedUp resume paths; obsolete `n21_paid_contract_retry_after_timeout` marker was incorrectly reporting a code gap.
- `eb08499`: V4 final acceptance matrix synchronized with exact known limits.
- Static connector readback covered 18 key files / 17 source integration call-link gates. 16/17 were present before correction of the **obsolete** N84 audit marker, now reconciled to the released N104 behavior. The modified seven candidate files were fetched at HEAD `40bfff2`: all GDScript delimiters/quote lines and new source preload paths checked (zero missing among those preloads), NUL-free, LF. **Not a complete real Python source-gate execution.**

## Important original Rust parity remaining (do NOT hide)

1. `economic_mandates` is now securely stored/controlled but the real **N109/N110 economy mandate authorization through exact N111 native quote -> actual N104/N9 paid contract -> simultaneous `spent_cr` and charter receipt** is **not yet full SOURCE_WIRED**. N134 source currently handles a narrower native N154 construction source; assigning economic directives does not automatically perform a paid strategy order. Do not credit money or infer a successful player instruction from a policy update.
2. N113 prior `supply` intents whose source original N135/N121 logistics comparison cannot be recovered from N154 are still **deliberately retained**; their original candidate value is not reconstructed and should not be marked extinct to unlock free migrations. This is a source-parity limitation separate from runtime crashes.
3. N158 provides the canonical player-policy API; UI controls/click wiring and actual local player permission context are not asserted.
4. The combined CI workflow only covers early Godot syntax/runtime smoke and one N143 paid research acceptance, **not the full A/Б/В/Г 10/100/1000-tick, N104 full delivery, N151 colony, N38 mid-flight/restore, Windows unpacked EXE/PCK end-to-end**.

## Immediately next and no new feature proliferation

- **Step 1 — inspect the single real CI run** triggered by `40bfff2`. Fix actual first parser/import/runtime FAIL from `godot-p2-unified-diagnostics` logs; one batch of fixes, not new speculative subprojects.
- **Step 2 — run exact source audit** in checkout: `python3 godot/tools/p2_v4_source_gate.py --require-complete --json`. Its success is SOURCE only; no claim of game performance. After parse success, add deferred N109/N110 and N113 test scripts to one follow-on acceptance batch as appropriate.
- **Step 3 — run one actual scenario A: market deficit → faction native paid N104/N9 → real N153 ship → N14 jump → N21 queue → N15 pick/deliver → real N9 receipt. Check balance before and after N38 midflight.**
- **Step 4 — scenario Б: genuine colony N151, physically funded passengers/600 Metals/150 paid shifts/20k N9, and В: N100/N134 real Head → N121 order rather than preview. Check cold/long 100/1000-tick soak vs paused FPS.**
- **Step 5 — Windows RC ZIP from `p2-windows-release.yml`, correct EXE + PCK + unchanged data JSON, unpack and actually launch.** Only after real PASS from all gates assign `SOURCE_INTEGRATION_COMPLETE`/integration VERIFIED.

Chat1 N21/N104 leases were RELEASED before this shared N158/N39 edit; no overlapping active lease touched. No balance changes, no new Godot tick, no extra simulated world, no repeated GitHub Actions.
