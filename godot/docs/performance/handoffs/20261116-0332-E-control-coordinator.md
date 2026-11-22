# PERF E handoff — 2026-11-16 03:32 CET

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

Code commit: `e989569f0cf321be9a329a867a2e3624074808b9`
Test commit: `b03a74e141a01bf292455a865e6314161bcc4deb`

Files:
- `godot/scripts/sim/phase2/n158_worker_control_coordinator.gd`
- `godot/tests/p2_perf_e_control_coordinator.gd`

Isolated owner-side FIFO+tick-scheduler coordinator. UI commands are accepted by the existing bridge; one owner drains them in order. Pause/resume/step/speed are applied to the admission scheduler, save/load require an explicit owner-local persistence executor and fail closed without one. Successful load resets the scheduler and invalidates the bridge FrameView epoch; failed load retains the committed frame. Failed authoritative tick freezes command acceptance. No World/N9/N38 duplication, no SceneTree access, no production wiring.

TEST EXECUTED: NOT RUN (Godot 4.7.2 unavailable). CODE_UNVERIFIED. Test added for command order, detached frame, failed persistence, save acknowledgement and failure freeze. FPS and TPS NOT MEASURED. No Actions triggered.

Risk: persistence executor contract and load transaction ordering require real N158/N38 parity tests; the module does not itself run a thread or authoritative simulation. Keep opt-in and do not enable in main.gd.

NEXT: add successful-load epoch/reset regression, integrate an owner-thread dispatcher with actual N158 API behind a disabled-by-default flag, then run N39/BT/RNG/N38 parity and GUI FPS benchmark before switching UI.
