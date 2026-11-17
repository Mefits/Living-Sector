# Figma Make V1 → Godot UI mapping

Source of truth: `App.tsx` and `index.css` in this directory. Do not treat JSX demo numbers as gameplay state.

| Figma Make CSS / React | Existing Godot implementation | Migration target |
| --- | --- | --- |
| `.app-shell`, `.topbar`, `TopBar` | `scripts/view/strategy_ui.gd::_build_top` | HUD structured with native containers + shared Theme |
| `.brand`, `.resources`, `Resource` | `strategy_ui.gd::_build_top` | Named resource metric and brand components |
| `.leftnav`, `LeftNav` | `strategy_ui.gd::_build_left` | `LSNavButton` |
| `.outliner`, `Outliner`, `OutlinerGroup` | `strategy_ui.gd::_build_outliner` | Reusable header, group, item |
| `.workspace-window`, `.workspace-titlebar` | `strategy_workspaces.gd::_ready` | `LSWindowPanel` |
| `.workspace-tabs` | `strategy_workspaces.gd::_tab_button` | `LSTabButton` |
| `.workspace-toolbar` | `strategy_workspaces.gd::_ready` | Reusable filtering toolbar |
| `.workspace-section` | `strategy_workspaces.gd::_section` | `LSSection` |
| `.metric-strip` | `strategy_workspaces.gd::_metric_strip` | `LSMetricLabel` |
| Tables / list rows | `strategy_workspaces.gd::_table_row` | Shared `LSTable` |
| `.statusbar` | `strategy_ui.gd::_build_footer` | Shared status bar |
| Icon SVG paths | `scripts/view/figma_strategy_icons.gd` | Reuse exact paths |

## Known geometry from V1

- Root grid: top HUD **58 px**, content area, footer **24 px**.
- Brand column: **192 px**.
- Left rail: **64 px**.
- Outliner: **264 px**.
- Workspace titlebar: **49 px**, tab strip **37 px**, toolbar approximately **35 px**.
- Main palette: background `#071019`, panel `#09141C`, line `#243942`, accent `#53B5AC`, text `#C4D0D3`, muted `#748B92`.
- Original font stack: IBM Plex Sans, Segoe UI, Arial, sans-serif. A bundled font is not yet present.

## Verification / incompleteness

- Original React/CSS source is pinned. Original Figma screenshots/bitmap assets still need archival; no pixel-parity claim yet.
- Desktop acceptance sizes: **1920×1080** and **1366×768**.
- Test must run under Godot 4.7.2; newly added theme resource and variation script have not passed a local Godot parser test here.
- Keep existing N39/N158 data and all selection/actions. For missing game data show unknown rather than copy Figma mock values.
