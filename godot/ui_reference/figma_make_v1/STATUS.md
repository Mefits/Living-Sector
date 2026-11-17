# Living Sector — native Godot UI transfer status

Source Figma Make: https://www.figma.com/make/ecvrssCEMaMqUObXlDkLzN/Living-Sector-Game-Interface

**Working branch:** `feature/SystemBalance`  
**Rule:** only check off work after its files are committed; Godot/runtime validation is a separate gate.  
**Source of truth for progress:** this file in GitHub (the tldraw view may not reliably persist changes).

## Stage 1 — Figma reference [IN PROGRESS]

- [x] Original `App.tsx` and `index.css` saved in `godot/ui_reference/figma_make_v1/`.
- [x] Initial CSS dimensions and component map saved.
- [ ] Capture and commit authoritative full-resolution screenshot(s) and required image assets.
- [ ] Confirm exact fonts and available font licensing/assets.

## Stage 2 — native Theme [IN PROGRESS]

- [x] `godot/ui/living_sector_theme.tres` with base Figma palette.
- [x] `ls_ui_theme.gd`: reusable variations for buttons, tabs, panels, typography and dense rows.
- [x] StrategyUI inherits the Theme, preserving existing local overrides until migration.
- [x] Workspace header, toolbar, search panel, window icon, section header, table rows **and outer management window shell** moved to Theme.
- [ ] Run Godot 4.7.2 headless parse and `godot/tests/p2_figma_ui_theme_check.gd`.
- [ ] Migrate remaining per-control StyleBox overrides and verify in a rendered game.

## Stage 3 — component library [IN PROGRESS]

- [x] `ls_ui_components.gd` factories for action buttons, tabs and metric labels/panels.
- [x] Reusable header/search/toolbar/section panel wrappers.
- [x] Reusable interactive and read-only table rows; original Figma dense-row colors/typography and hover states.
- [x] Workspace callbacks keep their original N39 actions and selection signals.
- [x] Theme-backed management window shell (original navigation logic remains).
- [ ] Shared flexible table-column layout and remaining controls.
- [ ] Visual screenshot comparisons.

## Stages 4–7 [NOT STARTED]

- [ ] Top HUD, left navigation, outliner and footer mapped 1:1.
- [ ] Seven workspace bodies visually matched to Figma.
- [ ] 1920×1080 and 1366×768 scaling and keyboard/mouse testing.
- [ ] Pixel-level screenshot verification + game behavior acceptance.

## Verification and safety

- No Godot executable available in this workspace; **tests above have not run**.
- No expensive GitHub Actions were triggered.
- Game engine/economy/AI N39/N158 and true live values remain authoritative.
- No temporary screenshot or mock data should be substituted for live game state.
- Visual parity **is not yet claimed**.

Newest substantive commits: `49f27b0` (chrome), `085f89c` (table row), `61737da` (dense-row CSS), `7cdf99c` (window shell).

Source-level consistency checks passed: all 7 `.tres` StyleBox subresources resolve; 22 named theme variations, 7 UI factories, 36 theme contract assertions. **These are not runtime tests.**
