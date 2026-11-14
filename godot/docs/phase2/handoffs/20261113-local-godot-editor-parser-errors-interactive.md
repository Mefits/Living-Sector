# P2 local Godot 4.7.2 editor-import parser corrections — user screenshot

User has opened the actual GitHub Desktop checkout in portable Godot 4.7.2 and reported parser error toasts for four tests: `n20_observer_check.gd`, `n30_contract_cargo_audit_check.gd`, `n57_live_native_fleet_engine_check.gd`, `n68_native_price_tick_check.gd`. Screenshot also showed a generic Unicode `Unexpected NUL character` message without the offending path.

Changes committed to common branch `integration/godot-phase2-unified-20261113`:
- `8be5c4ed`: renamed test-local preload `Projection` to `ObserverProjection`; Godot has a native `Projection` type.
- `d900ea73`: explicit `Dictionary` typing on dynamically obtained N30 cargo receipt.
- `b697e4c1`: renamed test-local preload `Engine` to `FleetEngine`; Godot has a native `Engine` class, exactly confirmed in screenshot at N57 line 5.
- `78defeaa`: explicit float conversion for N68 `price` looked up in a dictionary; inferred `:=` from variant was ambiguous.

**Verification:** all four remote script blobs UTF-8 string content contain zero NUL / U+FFFD and pass simple balanced delimiters. Full Godot 4.7.2 parser not available in this chat; `SOURCE_PATCHED_CODE_UNVERIFIED`; do NOT claim all errors resolved or that the generic NUL error is fixed. No source-gameplay changes. **Zero GitHub Actions runs.**

**Next local user workflow:** exit Godot completely, GitHub Desktop Fetch origin → Pull origin on `integration/godot-phase2-unified-20261113`, reopen full checkout `godot/project.godot`, wait for import, F5. Godot may show additional previously hidden parser errors; capture first full `Output`/Debugger Errors path+line after closing notifications. If **only generic NUL** remains and remote blobs match, clean the generated `godot/.godot/` cache with editor closed (never delete `project.godot`, `native`, `.git`), reopen and retry. If persistent, inspect the exact local file indicated by Godot, compare hash with HEAD; do not guess source file from unrelated toast. The N30 source content on GitHub is verified free of NUL, but user local checkout was not inspected directly.

Developers: reserve new test files before changing; don't spend Actions to verify just these parser edits. Prioritize fixing real Godot local errors in coherent batches and then resume Gate 2 single-runner fleet / economy integration.
