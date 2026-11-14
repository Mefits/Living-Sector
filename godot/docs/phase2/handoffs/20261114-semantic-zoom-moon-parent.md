# P2 — Three semantic UI levels and moon-parent display (14 Nov 2026)

**GitHub branch:** `integration/godot-phase2-unified-20261113`, shared Draft PR #249.

- Implemented 3 navigation levels without new simulation/World: double-click star → system, double-click planet/moon (or zoom toward visible body) → large flat, industrial-minimalist globe. Header Back now unwinds globe → orbital map → sector. Center resets current level.
- Rendering is flat visual-only, NOT actual terrain or plotted colonization/building slots. Body's genuine native biome and facility count remain visible; existing details inspector keeps live data.
- Frozen source moons have no `parent_body_id`, and every body's angle/period is currently evolved by Rust-equivalent independent `BodyOrbit::advance`. Original Godot map falsely drew Luna & Callisto as independent heliocentric rings. **UI-only** known factual mappings `luna→earth` and `callisto→jupiter` now center moon rings at the **moving** parent screen position, using the real live moon angle. Visual screen radius is intentionally schematic, not a claimed lunar distance or correct 28-day month. The simulator and saves are unchanged.
- Fictional `nadir-wreckhold` has NO known native parent; without lore confirmation it remains on the frozen, source-based schematic star orbit. Never infer a parent from nearest radius or fabricate a month.
- One check `godot/tests/p2_semantic_orbital_view_check.gd` reads actual frozen Sol and Nadir, asserts Luna and Callisto parent-centered rendering and live-angle movement, correct globe open/close with tick updates, and refuses unknown Wreckhold parent.
- **Static readback PASS** for scripts, balanced delimiters, NUL-free, preload paths present. **No Godot binary** in this environment; test prepared but NOT EXECUTED, no CI dispatched. Do not call it accepted game-runtime behavior.
- User acceptance after GitHub Desktop Pull: Godot F5, double-click Sol then Earth, globe appears and Back steps to Sol, then sector; on Sol watch Luna follow Earth (schematic), then Jupiter/Callisto; Nadir Wreckhold remains unparented until lore/model metadata added.
- Embedded Godot Game window sizing remains an Editor preference: change **⋮ next to 1366×768 → Stretch to Fit** or disable embedded Game and launch external, not just `project.godot` maximized mode.

**Source code commits:** `083cc68fe5` (view), `6344d25f7e` (navigation), `26cd77ab06` (one fixture).
