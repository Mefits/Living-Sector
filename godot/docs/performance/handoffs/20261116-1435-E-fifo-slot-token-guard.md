# PERF E · FIFO save/load slot token boundary · 2026-11-16 14:35 CET

- **Code commit:** `c927edabf8fee18d615f981f02ed0093bc614ddb`
- **Test commit:** `294c78ca394fb167f858d17294930f8cbe028738`
- **Files:** `godot/scripts/sim/phase2/n158_worker_command_fifo.gd`; `godot/tests/p2_perf_e_fifo_slot_token_boundary.gd`
- **Why:** save/load FIFO previously accepted arbitrary nonempty strings up to 128 chars as opaque slot tokens, including traversal, separators, URL-like strings and control characters. It now accepts ASCII letters, digits, underscore and hyphen only; maximum length remains 128. Both save and load use the same validation. Existing `autosave` behavior is unchanged.
- **Test:** CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime executed; no FPS/TPS measurements. Regression includes traversal, slashes, backslash, colon, whitespace, dot, newline, Unicode, overlength, and accepted tokens with FIFO acknowledgements.
- **Scope:** detached experimental FIFO only. No change to default backend, N158 cadence, N39, N9, N38, World, AI, or save codec. Does not claim to sanitize paths in other worker interfaces.
- **Next:** inspect real opt-in N158 save/load command translation for slot/path distinction; then run targeted test and real N38 restart parity checkpoint before any production toggle. Windows paused/×1/×8/×16 FPS remains unmeasured.
