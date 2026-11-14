# P2 pivot — autonomous sector first, 13.11.2026
- User explicitly rejects focus on per-ship manual micromanagement; individual N14/N21/N15 order/ship/cargo UI preserved as future debug feature but hidden by default.
- Common PR #249 commit `af7f618b0b3193470431a6a480c532d87adf7123`: `main.gd::ENABLE_DEBUG_MANUAL_FLEET_UI=false`, per-ship rows invisible, callbacks guarded, read-only autonomy-status banner added.
- `observer_panel.gd` states the truth: self-ticking paid production, population consumption and markets are active; N153/N135 agents still NOT attached to the unified P2 apply, fleet NOT autonomous.
- Source APIs N14 ship departure, N21 docking, N15 cargo and save/load remain unchanged for AI and later game control.
- New `AUTONOMY_FIRST_RU.md` is the top-priority acceptance contract; top of `P2_INTEGRATION_EXECUTION_PLAN_RU.md` and `P2_SHARED_HANDOFF_RU.md` updated to supersede manual UI work.
- Five existing scheduled P2 developer shifts had their prompts updated (schedules unchanged): prioritize N135 station needs and ContractBoard, N153/N80/N81/N84 ships, N104/N97 real paid contracts and cargo, finally N134/N100/N155 director — one physical World/Ledger/Apply/save, no fake visual traffic.
- Acceptance: hands-off fresh-world N39 demand → real funded order → autonomous selected ship → physical trip/commodity → receipt/settlement → inspector reason/result → restore without duplication. Before that, source code is NOT autonomously ready.
- Verification performed: remote script/doc readback after commit, no NUL, balanced script delimiters, UI flag and hidden rows check. Godot editor/game execution NOT run; no CI dispatched.
- Next owner: reserve one freed major independent AI/ContractBoard domain with fresh HEAD/claims; write executable actual end-to-end flow, not micro-PR guards or manual GUI.
