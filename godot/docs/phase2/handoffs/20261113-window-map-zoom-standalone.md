# Living Sector P2 — Windows game window + practical close zoom

- User report: F5 opens a tiny game window and sector/system maps cannot zoom close enough. This is a UI acceptance issue, **not** a request to reopen manual ship micromanagement.
- Shared branch `integration/godot-phase2-unified-20261113`, PR #249.
- `godot/project.godot`: set `window/size/mode=2` (maximized for **standalone** game), resizable; preserve 1366x768 logical canvas and existing stretch. Do not force absolute 1600x900 window on smaller screens.
- **Godot Editor 4.7 caveat**: Game embedding may override project window mode. Editor top **Game** tab → upper-right Game bar dropdown → uncheck **Embed Game on Next Play** (or change embedded fixed sizing to **Stretch to Fit**). Then F5 for actual standalone maximized game. This is an editor preference, not a repo/project defect; the project cannot force editor choice.
- `system_map.gd`: zoom range 0.4–32 (previous 0.45–8), wheel factor 1.32 (previous 1.18); pointer-anchored pan preserved, symbols modestly enlarge and stay pickable, current zoom shown in footer.
- `star_system_view.gd`: zoom range 0.45–32 (previous 0.55–5), same wheel and pointer anchoring; planet/star symbols now scale sublinearly with zoom, label/marker offsets and selection radius follow actual symbol size; current zoom shown on system map.
- No new World, Ledger, AI, manual controls or test suite. Existing **Центрировать карту** button resets both to 1.0.
- GitHub readback of all three edited files: brackets balanced, no NUL, valid Godot `sqrt()`, expected zoom/maximize settings present. **Godot editor unavailable, runtime result not confirmed**.
- One user acceptance instead of many tests: GitHub Desktop Fetch/Pull branch; Godot Editor Game → disable Embed Game on Next Play; F5; verify external window is maximized; move mouse over a system or planet and use wheel 8–12 notches to reach close zoom; drag by holding LMB; use **Центрировать карту** to reset. A screenshot/error only if this fails.
- Follow-up if user requests further UI: implement deliberate camera focus on selected system/body, not 100x orbit scaling or fake high-resolution surfaces. Do not conflate schematic map zoom with a new detailed surface-view feature.
