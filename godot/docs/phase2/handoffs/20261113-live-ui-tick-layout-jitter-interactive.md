# P2 user Windows F5 — tick-triggered horizontal UI resizing

User screenshot 13.11.2026, 18:30–18:45 MSK: while simulation runs, UI (sector map/inspector) periodically shifts sideways; paused time stabilizes layout. Godot 4.7.2; local UTF-8 scanner returned 378 source files, 0 suspect files; previous NUL import issue cleared.

**Verified in source** `godot/scripts/main.gd`: every `_on_tick_completed` calls `_update_status` and `_populate_ship_choices`. `_update_status` sometimes appends extra economic data (every 5 ticks). `_status` was a normal `Label` with intrinsic text-sized minimum width and no clipping; this pushes full-width VBox/main map whenever the string length increases. Every ship tick also repopulates an `OptionButton` with dynamic name/location, and default `fit_to_longest_item` can alter the row minimum width.

**Fix** commit `51ece365` (one file `godot/scripts/main.gd`):
- Status Label: `size_flags_horizontal=SIZE_EXPAND_FILL`, `clip_text=true`, `text_overrun_behavior=OVERRUN_TRIM_ELLIPSIS`, `custom_minimum_size=Vector2.ZERO`. This prevents time-dependent contents from changing horizontal minimum size.
- `_status.tooltip_text = _status.text`: retain complete status diagnostics on mouseover even if viewport too narrow.
- Ship dropdown: width min=250, `size_flags_horizontal=SIZE_SHRINK_BEGIN`, `fit_to_longest_item=false`, `clip_text=true`; contents may update, never resize entire panel.
- No economy/fleet/tick/save changes. Static balanced delimiters pass; real Windows Godot F5 retest **not performed by agent**; no Actions used.

**Important separate constraint:** if user has embedded Godot Game viewport narrower than required ~800px (map has 420px min + inspector 355px min + gaps), it will still be too narrow even after fixing status jitter. Recommend Game tab → top-right three dots → disable “Embed Game on Next Play” (or “Make Window Floating on Next Play”) and F5, then maximize/resize separate window. This is a display configuration workaround, not evidence the in-game UI has responsive design. Responsive compact UI is deferred to the next UI design macroblock, not hidden under one-time text patch.

User validation after GitHub Desktop Fetch/Pull: run F5, leave simulation for 20–30 ticks, see whether map/sidebar stay fixed even at tick multiples of 5; pause/resume several times. If still jumps, inspect screen after pull and capture window width / exact widget. No cloud Actions for this.
