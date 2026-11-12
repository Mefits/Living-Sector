# N36 — Godot startup compatibility handoff

Status: **CODE_UNVERIFIED**. Based on integration branch `integration/godot-foundation-smoke-20261112` (PR #120); no merge to main.

## What changed

- `scripts/main.gd`: exposes a read-only `startup_health()` dictionary (Godot runtime version, seed, map/UI readiness, tick, implemented phases) and preserves startup errors for diagnosis. No economic simulation or balancing change.
- `tests/n36_startup_compat_check.gd`: actually instantiates the main scene, checks seed and renderer-independent UI initialization, exercises pause/3-step/x16, observer open/close, and UI save/restore. A failure exits nonzero.
- No external plugin or 10,000-node scene. Uses built-in SceneTree/Control and native TickRunner.

## Windows smoke (Godot Standard 4.x)

From the `godot` directory (replace executable path):

```cmd
"C:\path\to\Godot.exe" --headless --editor --path . --quit
"C:\path\to\Godot.exe" --headless --path . --script res://tests/n36_startup_compat_check.gd
```

If an error occurs, save the Godot console output, `godot/logs/integration` and the precise Godot version. The project feature flag `4.3` is the minimum feature marker, not proof that code is incompatible with later Godot 4.x. Do not blindly replace it with 4.7.

## Limitations

The agent did not run Godot. The smoke checks UI-to-orbit TickRunner wiring, not the live P2/P3 domain systems; only `bodies` is currently advertised as implemented. The test writes to the default user save location; it is intended for a disposable local smoke environment. After the first actual Godot run, fix parser/runtime errors based on logs before promoting status to VERIFIED.
