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
- [x] Shared per-table column sizing profile: identical header/data widths, Figma five-column layout, four-column ID exception, and full-width clickable rows.
- [x] Shared navigation links and Figma issue alerts (47px, critical/normal variants, original callbacks).
- [ ] Remaining specialized controls and complete Windows visual comparison.
- [ ] Visual screenshot comparisons.

## Stage 4 — native HUD and peripheral shell [IN PROGRESS]

- [x] New Theme-backed 58px Figma header (was 82px+), 192px brand, 46px alert and compact N158 pause/×1/×16 controls.
- [x] Six actual N39 resource chips with icon/name/value layers; no invented market rates or Figma demo trends.
- [x] Existing FPS/SIM/UIFrame profiler values moved into the 24px statusbar, no new world snapshots.
- [x] 64px left navigation migrated to shared normal/selected Theme variants with existing game actions.
- [x] Right outliner shell and header migrated to shared Theme; responsive widths remain game-controlled.
- [x] Native selected-object card, map breadcrumb and simulation alert popover use shared Theme.
- [x] Native 42px outliner items and selected/hover Theme variants, 29px group headings, 29px glyphs, filter states.
- [x] Compact 10px titles / 8px hints for the outliner, no extra width or duplicate inline StyleBoxes.
- [ ] Remaining contextual details and nav utility controls; pixel-level correction waits for final acceptance.
- [ ] Windows visual comparisons and game behavior checks deliberately deferred until final acceptance (user instruction).

## Stage 5 — workspace bodies [CODE COMPLETE / NOT TESTED]

- [x] Shared 29px key–value rows and compact source-grounded notes across the seven workspaces.
- [x] Figma four-up metric strip layout, with responsive columns and no fabricated values.
- [x] Theme-backed production chain cards and conditional N39 facility condition meter (good/worn/critical).
- [x] Facility input → machine → output stage cards; only published N39 work_shift fields displayed, otherwise "—".
- [x] Economy, construction and fleet four-up KPI strips derived from existing N39 dictionaries.
- [x] Responsive two-column colony overview sections (Figma .workspace-grid).
- [x] N39-backed administration reasoning rows; no invented priorities or planner scores.
- [x] Research track styling with bars only when published points/required_points exist.
- [x] Ship cargo manifest and physical route stage cards from N14 transit; no estimated arrival percentages.
- [x] Specialized tabs: facility warehouse summary, N153 contract status summary, N39 construction stages / blockage reasons, confirmed planner priorities/consequences and research prerequisites/unlocks.
- [x] All seven workspace bodies now use the common Figma-native component vocabulary.
- [ ] Pixel-perfect visual acceptance remains in the final verification stage.
- [ ] Visual acceptance postponed until the end at user request.

## Stage 6 — adaptive geometry and integration [IN PROGRESS]

- [x] Pure `ls_ui_layout.gd` geometry policy uses the actual post-scaling Control size, rather than artificial 640px minimum.
- [x] Workspace receives priority over right outliner on narrow logical viewports; user can reopen it.
- [x] Window, breadcrumb, context card, alert popover and footer all derive offsets from the same layout.
- [x] Resource chip counts adapt at five width bands; no game state or N39 snapshot is read by layout.
- [x] Workspace metric grids and colony columns reflow by available logical workspace width, not their own resizes (no 4↔2 oscillation).
- [x] Tabs retain native horizontal scrolling and live search remains available in narrow windows.
- [ ] Finish small-screen card height, scroll overflow and remaining HUD controls.
- [ ] 1920×1080 and 1366×768 visual / input testing deferred until final stage 7.

## Stage 7 — final acceptance [NOT STARTED]

- [ ] Pixel-level screenshot verification + game behavior acceptance.

## Verification and safety

- Per user decision: **do not perform Godot tests or visual acceptance until the implementation is finished**. No Godot executable is available in this workspace.
- No expensive GitHub Actions were triggered.
- Game engine/economy/AI N39/N158 and true live values remain authoritative.
- No temporary screenshot or mock data should be substituted for live game state.
- Visual parity **is not yet claimed**.

Newest substantive commits: `9811ee9` (table column grid), `4a75eb7` (table profile tests), `5f46ff3` (alert/link Theme), `f9613ac` (alert/link use), `19e98bb` (contract tests).

Source-level consistency checks passed: all 7 `.tres` StyleBox subresources resolve; 25 named theme variations and 10 UI factories. New checks verify 4/5-column profiles, clickable-row anchors, navigation link and alert callbacks in source. **No Godot runtime tests were executed.** The layouts still need a real viewport screenshot comparison.

### Implementation checkpoint — 2026-11-18

- `eb2a417`: native 58px header, six live resource chips, FPS/SIM/UI footer and unchanged N158 speed actions.
- `adb22e1`: Figma 64px navigation rail and outliner shell.
- `60e5419`: shared Theme for context card, map breadcrumb and alerts.
- Full visual parity and runtime safety **not yet verified**; user requested checks only at completion.

- `2b02b75` / `f08b21e` / `da8caf1`: compact Theme-backed N39 outliner entries, icon frames, group headers, and live filter states.

- Implementation block: shared workspace primitives (key–value, notes, metric grid, chain stage and condition bar) now reuse LSTheme/LSComponents; **no Godot/runtime tests run**.

- Implementation block: source-backed facility process, colony 2-column layout, market/project/fleet status strips; no new world snapshots and **no tests run**.

- Implementation block: research, administration and ship detail views now use Theme-backed Figma rows/cards; missing telemetry is clearly marked; **no tests run**.

- Market credit aggregate is displayed only if every listed market publishes a numeric credit amount; partially reported totals remain "—".

- Latest implementation: bad3df2 (warehouse/contracts/planner/research), ae6da36 (construction stages and published AI consequences). Per user request, no Godot tests or Actions triggered.
