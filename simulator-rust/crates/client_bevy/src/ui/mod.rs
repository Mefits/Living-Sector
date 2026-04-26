//! egui-based inspector panels. First panel: perf overlay.
//!
//! Pattern for every panel: a Bevy system that opens an `egui::Window`
//! and reads the `Sim` Resource directly. Zero marshalling, zero
//! snapshot layer — the inspector IS a live debugger with full
//! access to every hecs component. This is the key payoff of the
//! embedded architecture vs. the Godot client's WS-and-JSON path.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts, EguiPlugin};
use std::time::{Duration, Instant};

use crate::camera::CameraResetRequest;
use crate::sim::{EventsLog, PhasePerf, Retirements, Sim, TickPerf};

mod construction;
mod contracts;
mod events;
mod facility;
mod factions;
mod format;
mod help;
mod icons;
mod labels;
mod markets;
mod menus;
mod minimap;
mod panel_stack;
mod populations;
mod retirements;
mod ship_details;
mod ship_list;
mod theme;

use construction::{construction_panel, ConstructionState};
use contracts::{contracts_panel, ContractsState};
use events::{events_panel, EventsState};
pub use facility::SelectedFacility;
use facility::{facility_details_panel, facility_list_panel, FacilityListState};
use factions::{factions_panel, FactionsState};
use help::{help_panel, HelpState};
use labels::{
    body_labels_panel, construction_labels_panel, facility_labels_panel, ship_labels_panel,
    BodyLabelsState,
};
use markets::{markets_panel, MarketsState};
use menus::{options_panel, pause_menu, OptionsState, PauseMenuState};
use minimap::{minimap_panel, MinimapState};
pub use panel_stack::{CloseTopRequest, OpenPanelStack};
use panel_stack::{close_top_panel, keyboard_shortcuts, reconcile_panel_stack};
use populations::{populations_panel, PopulationsState};
use retirements::{retirements_panel, RetirementsState};
use ship_details::ship_details_panel;
pub use ship_list::SelectedShip;
use ship_list::{ship_list, ShipListState};

pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(EguiPlugin)
            .init_resource::<PerfStats>()
            .init_resource::<ShipListState>()
            .init_resource::<ContractsState>()
            .init_resource::<FactionsState>()
            .init_resource::<MarketsState>()
            .init_resource::<PopulationsState>()
            .init_resource::<SelectedShip>()
            .init_resource::<FacilityListState>()
            .init_resource::<SelectedFacility>()
            .init_resource::<RetirementsState>()
            .init_resource::<ConstructionState>()
            .init_resource::<MinimapState>()
            .init_resource::<BodyLabelsState>()
            .init_resource::<EventsState>()
            .init_resource::<PauseMenuState>()
            .init_resource::<HelpState>()
            .init_resource::<OptionsState>()
            .init_resource::<SaveListState>()
            .init_resource::<NewUniverseDialogState>()
            .init_resource::<AddShipDialogState>()
            .init_resource::<AddFacilityDialogState>()
            .init_resource::<ContextMenuRequest>()
            .init_resource::<OpenPanelStack>()
            .init_resource::<CloseTopRequest>()
            // Always-on systems: theme + image loaders init egui state
            // regardless of state, and the main_menu_panel needs to
            // render in MainMenu state. Options window is reachable
            // from both states (main menu's Options button + pause
            // menu's Options button) so it lives outside the gate.
            .add_systems(
                Update,
                (
                    icons::install_image_loaders,
                    theme::apply_theme,
                    main_menu_panel.run_if(in_state(crate::AppState::MainMenu)),
                    new_universe_dialog.run_if(in_state(crate::AppState::MainMenu)),
                    options_panel,
                    save_list_panel,
                ),
            )
            // In-game UI: gated on `AppState::InGame`. MainMenu hides
            // the entire HUD; only the title screen + 3D backdrop
            // show. The chain keeps system order stable — top bar
            // first so available_rect is correct for the labels
            // farther down.
            .add_systems(
                Update,
                (
                    track_fps,
                    top_bar_controls,
                    top_bar,
                    perf_overlay,
                    ship_list,
                    contracts_panel,
                    factions_panel,
                    markets_panel,
                    populations_panel,
                    ship_details_panel,
                    minimap_panel,
                    body_labels_panel,
                    events_panel,
                    reconcile_panel_stack,
                    keyboard_shortcuts,
                    close_top_panel,
                )
                    .chain()
                    .run_if(in_state(crate::AppState::InGame)),
            )
            // Second chain keeps each system's parameter list small
            // enough that Bevy's tuple-of-params limit isn't an issue,
            // and also separates the "details" family so ship_details
            // + facility_details don't compete for EguiContexts within
            // the same chain.
            //
            // `.after(top_bar)` is critical for the *_labels_panel
            // systems — they call `ctx.available_rect()` to find out
            // where the top bar ends, and that only returns the
            // reduced rect AFTER `top_bar` has shown.
            .add_systems(
                Update,
                (
                    facility_list_panel,
                    facility_details_panel,
                    retirements_panel,
                    construction_panel,
                    pause_menu,
                    add_ship_dialog,
                    add_facility_dialog,
                    context_menu,
                    help_panel,
                    construction_labels_panel,
                    facility_labels_panel,
                    ship_labels_panel,
                )
                    .chain()
                    .after(top_bar)
                    .run_if(in_state(crate::AppState::InGame)),
            );
    }
}

/// Holo-chrome frame for the top-bar panels. Opaque navy base so
/// labels behind the panel can't bleed through, plus a faint
/// PRIMARY-tinted edge stroke for the holographic-glass cutoff.
/// Real backdrop blur would need a separate Bevy render pass that
/// samples the previous frame's color attachment — punting that
/// to a later bundle. Until then we fake the holo-glass feel via
/// `paint_holo_chrome_overlay` (dot grid + vertical gradient).
fn holo_chrome_frame() -> egui::Frame {
    egui::Frame {
        fill: theme::CHROME_BG,
        stroke: egui::Stroke::new(1.0, theme::PRIMARY_DIM),
        inner_margin: egui::Margin::symmetric(8.0, 4.0),
        outer_margin: egui::Margin::ZERO,
        rounding: egui::Rounding::ZERO,
        shadow: egui::epaint::Shadow::NONE,
    }
}

/// Paint the holo-glass texture overlay on top of a top-bar panel.
/// Subtle PRIMARY-tinted highlight at the top edge fading to
/// transparent toward the bottom — reads as an "interior glow" on
/// the chrome without a hard line.
///
/// Painted into a Foreground LayerId so it sits above the panel's
/// fill but BELOW interactive widget content (egui draws panel
/// chrome → our overlay → widget bg/fg → text).
fn paint_holo_chrome_overlay(painter: &egui::Painter, rect: egui::Rect) {
    let top = egui::Color32::from_rgba_premultiplied(20, 60, 95, 36);
    let bot = egui::Color32::from_rgba_premultiplied(0, 0, 0, 0);
    let mut mesh = egui::Mesh::default();
    let i0 = mesh.vertices.len() as u32;
    mesh.colored_vertex(rect.left_top(), top);
    mesh.colored_vertex(rect.right_top(), top);
    mesh.colored_vertex(rect.left_bottom(), bot);
    mesh.colored_vertex(rect.right_bottom(), bot);
    mesh.add_triangle(i0, i0 + 1, i0 + 2);
    mesh.add_triangle(i0 + 1, i0 + 3, i0 + 2);
    painter.add(egui::Shape::mesh(mesh));
}

/// Single top-bar system. Reads counts from the sim, hands out
/// open/close toggles to each panel's state Resource. Runs first
/// in the UI chain so the panels below see up-to-date `open`
/// flags the same frame the user clicks.
/// Pause / speed / tick readout / global controls (reset view,
/// save as). Split out from [`top_bar`] because Bevy caps system
/// param tuples at 16 and the combined set blew through that.
#[allow(clippy::too_many_arguments)]
fn top_bar_controls(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
    mut cam_reset: ResMut<CameraResetRequest>,
    mut save_req: ResMut<crate::sim::SaveAsRequest>,
    mut add_ship: ResMut<AddShipDialogState>,
    mut add_fac: ResMut<AddFacilityDialogState>,
    mut help: ResMut<HelpState>,
    mut ship_sel: ResMut<SelectedShip>,
    mut fac_sel: ResMut<SelectedFacility>,
    mut follow: ResMut<crate::camera::CameraFollow>,
    mut menu: ResMut<PauseMenuState>,
) {
    let resp_controls = egui::TopBottomPanel::top("top_bar_controls")
        .frame(holo_chrome_frame())
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new("spaceproject").strong());
                ui.separator();
                // Pause / play — icon-only square button. Hover surfaces
                // the action text since the icon alone is unambiguous
                // (▶ play, ⏸ pause).
                let running = sim.running;
                let pp_resp = ui
                    .add(egui::ImageButton::new(if running {
                        icons::pause()
                    } else {
                        icons::play()
                    }))
                    .on_hover_text(if running { "Pause" } else { "Play" });
                if pp_resp.clicked() {
                    sim.running = !running;
                }
                // UI labels are the pretty 1×/2×/5×/10× scale.
                // Internally these ARE the tick_mult values that
                // drive how many sim-tick iterations run per
                // FixedUpdate. The "real" world-speed (0.25 ×
                // tick_mult) is a code-internal anchor matching the
                // Godot baseline; we don't surface it because the
                // round numbers read better in-game.
                let mut speed = sim.tick_mult.max(1);
                egui::ComboBox::from_id_salt("sim_speed_combo")
                    .selected_text(format!("{}×", speed))
                    .show_ui(ui, |ui| {
                        for &s in &[1u32, 2, 5, 10] {
                            if ui
                                .selectable_value(&mut speed, s, format!("{}×", s))
                                .clicked()
                            {
                                sim.tick_mult = s;
                            }
                        }
                    })
                    .response
                    .on_hover_text(
                        "Sim speed. 1× is the chill default (Earth–Mars ≈ 4 min); \
                     10× fast-forwards for watching economic convergence. \
                     Each step runs that many tick-loop iterations per \
                     FixedUpdate.",
                    );
                ui.separator();
                ui.label(
                    egui::RichText::new(format!("tick {}", sim.tick))
                        .monospace()
                        .color(theme::TEXT_DIM),
                )
                .on_hover_text(
                    "Current sim tick. Each tick advances all agents one step \
                 (planner, market, facility, etc). Cadence = 8 ticks/sec × \
                 tick_mult; world-speed selector above maps that to a \
                 user-facing 0.25×–2.5× scale.",
                );
                if !sim.running {
                    // Always-visible PAUSED chip so users glancing at the
                    // top bar see why nothing's moving — separate from
                    // the pause-menu overlay which only shows when Esc is
                    // pressed.
                    ui.label(
                        egui::RichText::new("· PAUSED")
                            .strong()
                            .small()
                            .color(theme::WARN),
                    );
                }
                ui.separator();
                if ui
                    .add(egui::Button::image_and_text(icons::refresh(), "Reset view"))
                    .on_hover_text("Snap the camera back to the galactic overview starting pose.")
                    .clicked()
                {
                    cam_reset.0 = true;
                }
                if ui
                    .add(egui::Button::image_and_text(icons::save(), "Save as…"))
                    .on_hover_text(
                        "Write a timestamped VACUUM INTO snapshot of sim.db next to \
                     the current DB. Embedded client has no persistence worker \
                     yet, so the snapshot reflects the load tick rather than \
                     live state.",
                    )
                    .clicked()
                {
                    save_req.0 = true;
                }
                ui.separator();
                ui.label(egui::RichText::new("admin:").small().color(theme::TEXT_DIM));
                if ui
                    .add(egui::Button::image_and_text(icons::add_ship(), "+Ship"))
                    .on_hover_text(
                        "Open the Add Ship dialog — class / faction / location / \
                     credits / name. Not persisted (embedded client has no \
                     worker yet).",
                    )
                    .clicked()
                {
                    add_ship.open = !add_ship.open;
                }
                if ui
                    .add(egui::Button::image_and_text(icons::add_facility(), "+Fac"))
                    .on_hover_text(
                        "Open the Add Facility dialog — type / body / faction / \
                     docking capacity / credits. Not persisted yet.",
                    )
                    .clicked()
                {
                    add_fac.open = !add_fac.open;
                }
                ui.separator();
                // Menu button — opens the pause overlay (Save As / Options
                // / Return to Main Menu / Quit). Mirrors the `P` shortcut.
                // Esc still works the panel-stack flow first; this gives
                // users a one-click escape to game-level controls.
                if ui
                    .button("Menu")
                    .on_hover_text(
                        "Open the pause menu (also `P`). Esc dismisses panels \
                     one at a time before reaching the menu.",
                    )
                    .clicked()
                    && !menu.open
                {
                    menu.open = true;
                    menu.was_running = sim.running;
                    sim.running = false;
                }
                // Help / hotkey reference. Tiny "?" button at the end of
                // the controls row so the binding is discoverable
                // without first reading docs.
                if ui
                    .small_button("?")
                    .on_hover_text("Show keyboard + mouse hotkey reference (also `?` or `H`).")
                    .clicked()
                {
                    help.open = !help.open;
                }

                // Selection / follow chips — surface state from the
                // right-click context menu so users always have a way
                // to back out without remembering keys. Right-aligned
                // chain (rightmost first because of right_to_left
                // layout): clear-selection + selection label, then
                // unfollow + follow label.
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let any_selected = ship_sel.0.is_some() || fac_sel.0.is_some();
                    if any_selected {
                        if ui
                            .small_button("✕ Clear")
                            .on_hover_text("Deselect the current ship / facility (Esc).")
                            .clicked()
                        {
                            ship_sel.0 = None;
                            fac_sel.0 = None;
                        }
                        let label = if let Some(ref id) = ship_sel.0 {
                            format!("ship · {id}")
                        } else if let Some(ref id) = fac_sel.0 {
                            format!("facility · {id}")
                        } else {
                            String::new()
                        };
                        ui.label(
                            egui::RichText::new(label)
                                .small()
                                .monospace()
                                .color(theme::PRIMARY),
                        );
                    }
                    if let Some(target) = follow.target.clone() {
                        ui.separator();
                        if ui
                            .small_button("✕ Unfollow")
                            .on_hover_text("Stop the camera-follow lock (or pan manually).")
                            .clicked()
                        {
                            follow.target = None;
                            follow.snap_distance = None;
                            follow.mode = crate::camera::CameraFollowMode::default();
                        }
                        let label = match target {
                            crate::camera::CameraFollowTarget::Ship(id) => {
                                format!("◎ ship · {id}")
                            }
                            crate::camera::CameraFollowTarget::Facility(id) => {
                                format!("◎ facility · {id}")
                            }
                        };
                        ui.label(
                            egui::RichText::new(label)
                                .small()
                                .monospace()
                                .color(theme::SUCCESS),
                        );
                    }
                });
            });
        });
    // Holo-glass overlay (dot grid + vertical gradient) painted on
    // top of the panel fill. Foreground LayerId so it sits above
    // the chrome but underneath any popups / windows the panel
    // toggles open elsewhere.
    let painter = ctx.ctx_mut().layer_painter(egui::LayerId::new(
        egui::Order::Foreground,
        egui::Id::new("top_bar_controls_overlay"),
    ));
    paint_holo_chrome_overlay(&painter, resp_controls.response.rect);
}

#[allow(clippy::too_many_arguments)]
fn top_bar(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    retirements: Res<Retirements>,
    mut perf: ResMut<PerfStats>,
    mut ships: ResMut<ShipListState>,
    mut contracts: ResMut<ContractsState>,
    mut factions: ResMut<FactionsState>,
    mut markets: ResMut<MarketsState>,
    mut pops: ResMut<PopulationsState>,
    mut facilities: ResMut<FacilityListState>,
    mut retired_state: ResMut<RetirementsState>,
    mut construction: ResMut<ConstructionState>,
    mut minimap: ResMut<MinimapState>,
    mut body_labels: ResMut<BodyLabelsState>,
    mut events_state: ResMut<EventsState>,
    events: Res<EventsLog>,
) {
    // Count construction sites via an ECS query — the sim store
    // doesn't index them by id (sites aren't frequently looked up
    // by id). At typical counts (<20) the iteration is trivial.
    use sim_core::agents::construction::ConstructionSite;
    let construction_count = sim.store.world.query::<&ConstructionSite>().iter().count();
    let resp_panels = egui::TopBottomPanel::top("top_bar_panels")
        .frame(holo_chrome_frame())
        .show(ctx.ctx_mut(), |ui| {
        ui.horizontal(|ui| {
            // Panel-toggle row: each entry is icon + "Label (count)".
            // Click toggles the panel's `open` flag. The toggled
            // state is shown by the button's `selected` highlight,
            // not a separate visual cue, so the row stays uniform
            // when half the panels are open.
            if icon_toggle_with_tip(
                ui,
                icons::perf(),
                "Perf",
                None,
                perf.open,
                Some("FPS, ticks/sec, p50/p99 tick compute, phase breakdown."),
            ) {
                perf.open = !perf.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::ships(),
                "Ships",
                Some(sim.store.ship_by_id.len()),
                ships.open,
                Some("Sortable / filterable fleet roster. Click a row to inspect."),
            ) {
                ships.open = !ships.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::contracts(),
                "Contracts",
                Some(sim.store.contracts.iter().count()),
                contracts.open,
                Some("All 6 contract kinds with kind / status filters and expiry visibility."),
            ) {
                contracts.open = !contracts.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::factions(),
                "Factions",
                Some(sim.store.faction_by_id.len()),
                factions.open,
                Some("Treasuries, member counts, active subsidies, pairwise relations matrix."),
            ) {
                factions.open = !factions.open;
            }
            // Markets live in the ECS under MarketIdentity — counted
            // by iterating the world in the panel itself. Top-bar
            // label just says "Markets" without a count to keep the
            // shared top_bar system from having to query hecs too.
            if icon_toggle_with_tip(
                ui,
                icons::market(),
                "Markets",
                None,
                markets.open,
                Some("Per-location commodity prices, supply / demand, crisis flags."),
            ) {
                markets.open = !markets.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::pops(),
                "Pops",
                Some(sim.store.population_by_id.len()),
                pops.open,
                Some("Population census — count, sentiment, food, wealth, migration."),
            ) {
                pops.open = !pops.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::factory(),
                "Facilities",
                Some(sim.store.facility_by_id.len()),
                facilities.open,
                Some("Stations, refineries, factories, gates. Click a row to inspect."),
            ) {
                facilities.open = !facilities.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::ledger(),
                "Retired",
                Some(retirements.0.len()),
                retired_state.open,
                Some("Decommissioned ship ledger — broke / hoard / admin reasons."),
            ) {
                retired_state.open = !retired_state.open;
            }
            if icon_toggle_with_tip(
                ui,
                icons::barrier(),
                "Construction",
                Some(construction_count),
                construction.open,
                Some("Active construction sites accruing commodity deliveries toward materialisation."),
            ) {
                construction.open = !construction.open;
            }
            if ui
                .selectable_label(minimap.open, "Map")
                .on_hover_text("Top-down minimap. Click anywhere on it to recenter the camera.")
                .clicked()
            {
                minimap.open = !minimap.open;
            }
            if ui
                .selectable_label(body_labels.show, "Labels")
                .on_hover_text("Show / hide the body name labels overlaid on the 3D scene.")
                .clicked()
            {
                body_labels.show = !body_labels.show;
            }
            if icon_toggle_with_tip(
                ui,
                icons::events(),
                "Events",
                Some(events.0.len()),
                events_state.open,
                Some("Rolling event log — docks, deliveries, level-ups, crises, retirements."),
            ) {
                events_state.open = !events_state.open;
            }
        });
    });
    let painter = ctx.ctx_mut().layer_painter(egui::LayerId::new(
        egui::Order::Foreground,
        egui::Id::new("top_bar_panels_overlay"),
    ));
    paint_holo_chrome_overlay(&painter, resp_panels.response.rect);
}

/// Icon + label + optional `(count)` toggle button. Highlights when
/// `open` is true (egui Button's `selected` styling, no frame). Used
/// for every entry in the panel-toggles row so the top bar stays
/// uniform and visually scannable.
/// Icon + label + optional `(count)` toggle button with a hover
/// tooltip. The default tip is the label itself; pass `Some(...)`
/// for richer text. egui's hover delay (~250 ms) keeps the bar
/// quiet on quick mouse-overs. Button highlights when `open` is
/// true (egui's `selected` styling, frameless).
fn icon_toggle_with_tip(
    ui: &mut egui::Ui,
    icon: egui::Image<'static>,
    label: &str,
    count: Option<usize>,
    open: bool,
    tooltip: Option<&str>,
) -> bool {
    let text = match count {
        Some(n) => format!("{label} ({n})"),
        None => label.to_string(),
    };
    let resp = ui.add(
        egui::Button::image_and_text(icon, text)
            .selected(open)
            .frame(false),
    );
    let tip = tooltip.unwrap_or(label);
    let resp = resp.on_hover_text(tip);
    resp.clicked()
}

/// Rolling FPS window so the overlay doesn't flicker frame-to-frame.
/// Tracks the last N frame durations and averages them. Also carries
/// the panel's `open` flag — keeping it on the same Resource avoids
/// a second init_resource just for one bool.
#[derive(Resource)]
struct PerfStats {
    frame_samples: Vec<Duration>,
    last_frame_instant: Instant,
    avg_fps: f32,
    /// Rolling window of (wall_time, sim_tick) samples for the
    /// derived ticks-per-second readout. Compared against the
    /// configured target (8 × tick_mult) to flag when the sim
    /// is falling behind. Bounded at TPS_WINDOW; older entries
    /// pop off the front each tracking pass.
    tick_samples: std::collections::VecDeque<(Instant, u64)>,
    avg_tps: f32,
    /// Whether the Perf window renders. Default true — the perf
    /// readout is the primary always-on overlay during dev. Top
    /// bar gives you a button to hide it when a panel needs the
    /// space (it's anchored top-left and fights for room with the
    /// Ships toggle).
    open: bool,
}

impl Default for PerfStats {
    fn default() -> Self {
        // Honour CLIENT_BEVY_OPEN_PANELS for parity with the other
        // panels — but default to closed for normal sessions. The
        // perf panel was the last one defaulting to open and felt
        // intrusive once the rest of the UX matured.
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("perf") || s == "all")
            .unwrap_or(false);
        Self {
            frame_samples: Vec::with_capacity(FPS_WINDOW),
            last_frame_instant: Instant::now(),
            avg_fps: 0.0,
            tick_samples: std::collections::VecDeque::with_capacity(TPS_WINDOW),
            avg_tps: 0.0,
            open: auto_open,
        }
    }
}

const FPS_WINDOW: usize = 60;
/// TPS sampling window — 60 entries × 1 sample-per-frame at 60 fps
/// is a 1-second window, plenty to smooth out tick-mult bursts
/// while still surfacing meaningful drops.
const TPS_WINDOW: usize = 60;

fn track_fps(mut stats: ResMut<PerfStats>, sim: Res<Sim>) {
    let now = Instant::now();
    let dt = now.saturating_duration_since(stats.last_frame_instant);
    stats.last_frame_instant = now;
    if stats.frame_samples.len() == FPS_WINDOW {
        stats.frame_samples.remove(0);
    }
    stats.frame_samples.push(dt);
    if !stats.frame_samples.is_empty() {
        let sum: Duration = stats.frame_samples.iter().sum();
        let avg_secs = sum.as_secs_f32() / stats.frame_samples.len() as f32;
        if avg_secs > 0.0 {
            stats.avg_fps = 1.0 / avg_secs;
        }
    }

    // Tick-rate sampling: record (wall_time, tick) each frame.
    // TPS = (newest_tick - oldest_tick) / window_seconds.
    let tick = sim.tick;
    if stats.tick_samples.len() >= TPS_WINDOW {
        stats.tick_samples.pop_front();
    }
    stats.tick_samples.push_back((now, tick));
    if let (Some(&(t0, k0)), Some(&(t1, k1))) =
        (stats.tick_samples.front(), stats.tick_samples.back())
    {
        let secs = t1.saturating_duration_since(t0).as_secs_f32();
        if secs > 0.05 {
            let dticks = k1.saturating_sub(k0) as f32;
            stats.avg_tps = dticks / secs;
        }
    }
}

fn perf_overlay(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut stats: ResMut<PerfStats>,
    tick_perf: Res<TickPerf>,
    phase: Res<PhasePerf>,
) {
    if !stats.open {
        return;
    }
    let mut open = stats.open;
    egui::Window::new("Perf")
        // Anchor below the two-row top bar so the panel doesn't
        // sit on top of the panel-toggle row (≈52 px tall: one
        // row of controls, one row of panel toggles).
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(8.0, 60.0))
        .default_width(220.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            egui::Grid::new("perf_grid")
                .num_columns(2)
                .spacing([12.0, 4.0])
                .show(ui, |ui| {
                    // Helper: dim label column matches the holographic
                    // theme — keys read as muted captions, values pop
                    // in TEXT or status colour.
                    let key = |s: &str| egui::RichText::new(s).color(theme::TEXT_DIM);

                    ui.label(key("FPS"));
                    ui.colored_label(
                        theme::status_color(stats.avg_fps, (55.0, 30.0)),
                        format!("{:.0}", stats.avg_fps),
                    );
                    ui.end_row();

                    ui.label(key("Tick"));
                    ui.label(format!("{}", sim.tick));
                    ui.end_row();

                    // Sim TPS — actual ticks/sec from the rolling
                    // window, coloured against the configured target
                    // (DEFAULT_TICK_INTERVAL_S = 0.125 → 8 tps ×
                    // tick_mult). Green when keeping up, amber within
                    // ~25%, red when significantly behind.
                    ui.label(key("TPS"));
                    let target = 8.0 * sim.tick_mult.max(1) as f32;
                    let tps_color =
                        theme::status_color(stats.avg_tps, (target * 0.95, target * 0.75));
                    ui.colored_label(tps_color, format!("{:.1} / {:.0}", stats.avg_tps, target));
                    ui.end_row();

                    // Tick-compute p50/p99 (ms). FixedUpdate fires at
                    // 125 ms; well under means headroom for higher
                    // tick_mult. Approaching 125 ms = sim is the
                    // bottleneck.
                    let p50_ms = tick_perf.p50_us as f32 / 1000.0;
                    let p99_ms = tick_perf.p99_us as f32 / 1000.0;
                    ui.label(key("Tick p50"));
                    ui.colored_label(
                        theme::status_color_inv(p50_ms, (30.0, 80.0)),
                        format!("{p50_ms:.1} ms"),
                    );
                    ui.end_row();

                    ui.label(key("Tick p99"));
                    ui.colored_label(
                        theme::status_color_inv(p99_ms, (80.0, 125.0)),
                        format!("{p99_ms:.1} ms"),
                    );
                    ui.end_row();

                    ui.label(key("Ships"));
                    ui.label(format!("{}", sim.store.ship_by_id.len()));
                    ui.end_row();

                    ui.label(key("Facilities"));
                    ui.label(format!("{}", sim.store.facility_by_id.len()));
                    ui.end_row();

                    ui.label(key("Bodies"));
                    ui.label(format!("{}", sim.store.body_by_id.len()));
                    ui.end_row();

                    ui.label(key("Populations"));
                    ui.label(format!("{}", sim.store.population_by_id.len()));
                    ui.end_row();

                    ui.label(key("Factions"));
                    ui.label(format!("{}", sim.store.faction_by_id.len()));
                    ui.end_row();

                    ui.label(key("Contracts"));
                    ui.label(format!("{}", sim.store.contracts.iter().count()));
                    ui.end_row();

                    ui.label(key("World seed"));
                    ui.label(
                        egui::RichText::new(format!("{}", sim.world_seed))
                            .small()
                            .monospace(),
                    );
                    ui.end_row();
                });
            ui.separator();
            // Per-phase breakdown of the most recent tick — sums
            // approximately to tick_p50 (last-tick-wins for
            // tick_mult > 1). Names mirror the sim_server tick
            // phases. Sorted by decreasing cost so the dominant
            // phase is at the top.
            egui::CollapsingHeader::new("Phases (last tick µs)")
                .default_open(false)
                .show(ui, |ui| {
                    let mut rows: Vec<(&str, u64)> = vec![
                        ("ships", phase.ships_us),
                        ("apply1", phase.apply1_us),
                        ("apply2", phase.apply2_us),
                        ("facilities", phase.facilities_us),
                        ("markets", phase.markets_us),
                        ("populations", phase.populations_us),
                        ("factions", phase.factions_us),
                        ("relations", phase.relations_us),
                        ("regen", phase.regen_us),
                        ("crisis", phase.crisis_us),
                        ("dock_queue", phase.dock_queue_us),
                        ("drains", phase.drains_us),
                        ("bodies", phase.bodies_us),
                        ("events_log", phase.events_log_us),
                    ];
                    rows.sort_by(|a, b| b.1.cmp(&a.1));
                    egui::Grid::new("phase_grid")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            for (name, us) in rows {
                                ui.label(egui::RichText::new(name).small().color(theme::TEXT_DIM));
                                ui.label(
                                    egui::RichText::new(format!("{:.2} ms", us as f32 / 1000.0))
                                        .small()
                                        .monospace(),
                                );
                                ui.end_row();
                            }
                        });
                });
            ui.separator();
            ui.label(
                egui::RichText::new("embedded sim — no network")
                    .small()
                    .italics()
                    .color(theme::TEXT_DIM),
            );
        });
    // Write the close-button click back so future frames respect
    // it. egui's Window builder writes `false` into `open` when the
    // user clicks the X header button.
    stats.open = open;
}

/// Right-click context menu state. `target` = whatever the right-
/// click raycast hit (ship or facility, by sim_id); `screen_pos`
/// anchors the popup. `target = None` means the menu is hidden.
/// Set by `render::raycast_context_menu`; read + actioned by
/// [`context_menu`].
#[derive(Resource, Default)]
pub struct ContextMenuRequest {
    pub target: Option<ContextMenuTarget>,
    pub screen_pos: Vec2,
}

#[derive(Clone, Debug)]
pub enum ContextMenuTarget {
    Ship(String),
    Facility(String),
}

/// Render the right-click menu when a target is set. Items:
/// - **Inspect** — selects the entity (opens its details panel).
/// - **Follow** — locks the orbit camera's focus to the entity each
///   frame; user pan clears the lock.
/// - **POV** — same as Follow but snaps the orbit distance closer
///   for a near-camera "above the shoulder" feel. Not a true 1st-
///   person; defer real POV until we land a separate camera mode.
/// - **Destroy** — fires the matching DeleteShipRequest /
///   DeleteFacilityRequest. No confirmation — admin tool, embedded
///   client, undo == restart.
///
/// Closes on click-away. Egui's `Area::interactable(true)` keeps
/// hover events flowing; we close manually when an item fires or
/// when the user clicks outside the menu rect.
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_arguments)]
fn context_menu(
    mut ctx: EguiContexts,
    mut menu: ResMut<ContextMenuRequest>,
    mut ship_sel: ResMut<SelectedShip>,
    mut fac_sel: ResMut<SelectedFacility>,
    mut follow: ResMut<crate::camera::CameraFollow>,
    mut delete_ship: ResMut<crate::sim::DeleteShipRequest>,
    mut delete_fac: ResMut<crate::sim::DeleteFacilityRequest>,
    buttons: Res<ButtonInput<MouseButton>>,
    // Tracks the menu target seen on the previous frame. When the
    // current frame's target differs (None → Some, or a fresh
    // right-click on a different entity), we skip the click-outside
    // dismiss check for one frame so the very right-click that
    // opened the menu doesn't also close it. egui's
    // is_pointer_over_area() returns false on the spawn frame
    // because the area hasn't been registered yet, which made the
    // menu flash open for one frame and then auto-close.
    mut prev_target: Local<Option<ContextMenuTarget>>,
) {
    let Some(target) = menu.target.clone() else {
        *prev_target = None;
        return;
    };
    let just_opened = !matches!(&*prev_target, Some(t) if std::mem::discriminant(t) == std::mem::discriminant(&target)
    && match (t, &target) {
        (ContextMenuTarget::Ship(a), ContextMenuTarget::Ship(b)) => a == b,
        (ContextMenuTarget::Facility(a), ContextMenuTarget::Facility(b)) => a == b,
        _ => false,
    });

    let pos = menu.screen_pos;
    let mut close = false;
    let label_kind = match &target {
        ContextMenuTarget::Ship(id) => format!("Ship · {id}"),
        ContextMenuTarget::Facility(id) => format!("Facility · {id}"),
    };

    let ctx_ref = ctx.ctx_mut();
    egui::Area::new(egui::Id::new("context_menu_area"))
        .fixed_pos(egui::pos2(pos.x, pos.y))
        .order(egui::Order::Foreground)
        .show(ctx_ref, |ui| {
            egui::Frame::popup(ui.style())
                .stroke(egui::Stroke::new(1.0, theme::PRIMARY_DIM))
                .show(ui, |ui| {
                    ui.set_min_width(160.0);
                    ui.label(
                        egui::RichText::new(label_kind)
                            .small()
                            .color(theme::TEXT_DIM),
                    );
                    ui.separator();
                    if ui.button("Inspect").clicked() {
                        match &target {
                            ContextMenuTarget::Ship(id) => {
                                ship_sel.0 = Some(id.clone());
                                fac_sel.0 = None;
                            }
                            ContextMenuTarget::Facility(id) => {
                                fac_sel.0 = Some(id.clone());
                                ship_sel.0 = None;
                            }
                        }
                        close = true;
                    }
                    if ui.button("Follow").clicked() {
                        follow.target = Some(match &target {
                            ContextMenuTarget::Ship(id) => {
                                crate::camera::CameraFollowTarget::Ship(id.clone())
                            }
                            ContextMenuTarget::Facility(id) => {
                                crate::camera::CameraFollowTarget::Facility(id.clone())
                            }
                        });
                        follow.mode = crate::camera::CameraFollowMode::Lock;
                        follow.snap_distance = None;
                        close = true;
                    }
                    if ui.button("POV").clicked() {
                        follow.target = Some(match &target {
                            ContextMenuTarget::Ship(id) => {
                                crate::camera::CameraFollowTarget::Ship(id.clone())
                            }
                            ContextMenuTarget::Facility(id) => {
                                crate::camera::CameraFollowTarget::Facility(id.clone())
                            }
                        });
                        // True third-person chase camera —
                        // apply_camera_follow's Pov branch overrides
                        // yaw / pitch / distance from the ship's
                        // heading each frame. snap_distance left
                        // None; Pov owns its own distance.
                        follow.mode = crate::camera::CameraFollowMode::Pov;
                        follow.snap_distance = None;
                        close = true;
                    }
                    ui.separator();
                    if ui
                        .button(egui::RichText::new("Destroy").color(theme::DANGER))
                        .clicked()
                    {
                        match &target {
                            ContextMenuTarget::Ship(id) => {
                                delete_ship.0 = Some(id.clone());
                                if ship_sel.0.as_deref() == Some(id.as_str()) {
                                    ship_sel.0 = None;
                                }
                            }
                            ContextMenuTarget::Facility(id) => {
                                delete_fac.0 = Some(id.clone());
                                if fac_sel.0.as_deref() == Some(id.as_str()) {
                                    fac_sel.0 = None;
                                }
                            }
                        }
                        close = true;
                    }
                });
        });

    // Click-outside close: a left-click while the cursor is NOT
    // over any egui area dismisses the menu (the menu itself is an
    // egui Area, so clicks on it return is_pointer_over_area=true).
    // We DON'T listen for right-click here — the right-click that
    // opens the menu is consumed by raycast_context_menu, which
    // either re-targets to a new entity or leaves an empty-space
    // click as a no-op. Listening here would race with that path.
    //
    // Skip the dismiss check on the spawn frame (just_opened) so
    // the same right-click that opened the menu doesn't immediately
    // close it before egui registered the area's hover region.
    let click_outside =
        !just_opened && buttons.just_pressed(MouseButton::Left) && !ctx_ref.is_pointer_over_area();
    if close || click_outside {
        menu.target = None;
        *prev_target = None;
    } else {
        *prev_target = Some(target);
    }
}

/// State for the "Add Ship" admin dialog. Open/close via the
/// top-bar "+Ship" button. Form fields persist between openings so
/// repeated test spawns don't make the user re-pick everything.
#[derive(Resource)]
struct AddShipDialogState {
    open: bool,
    class: String,
    faction_id: String,
    location_name: String,
    credits: i64,
    name: String,
}

impl Default for AddShipDialogState {
    fn default() -> Self {
        Self {
            open: false,
            class: "freighter".to_string(),
            faction_id: "independent".to_string(),
            location_name: "earth-station".to_string(),
            credits: 5_000,
            name: String::new(),
        }
    }
}

const SHIP_CLASSES: &[&str] = &["courier", "freighter", "hauler", "tanker", "miner"];

fn add_ship_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<AddShipDialogState>,
    sim: Res<Sim>,
    mut spawn_req: ResMut<crate::sim::SpawnShipRequest>,
) {
    if !state.open {
        return;
    }

    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};

    // Build picker options from the live world. Factions come from
    // the faction_by_id index; locations from facility ECS data.
    // Sorted + deduped so the dropdowns are stable across frames
    // (hashmap iteration order isn't).
    let mut factions: Vec<String> = sim.store.faction_by_id.keys().cloned().collect();
    factions.sort();

    let location_set: std::collections::BTreeSet<String> = sim
        .store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .filter_map(|(_e, (id, loc))| {
            // Skip gates as spawn destinations — gates aren't dock
            // points and admin_spawn_ship at a gate gets the ship
            // immediately reset by the gate logic. Stations / mines /
            // factories / refineries / farms / outposts only.
            if id.facility_type == "gate" {
                None
            } else {
                Some(loc.location_name.clone())
            }
        })
        .collect();
    let locations: Vec<String> = location_set.into_iter().collect();

    let mut open = state.open;
    let mut spawn_clicked = false;
    egui::Window::new("Add Ship")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            egui::Grid::new("add_ship_form")
                .num_columns(2)
                .spacing([12.0, 6.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Class"));
                    egui::ComboBox::from_id_salt("add_ship_class")
                        .selected_text(&state.class)
                        .show_ui(ui, |ui| {
                            for &c in SHIP_CLASSES {
                                ui.selectable_value(&mut state.class, c.to_string(), c);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Faction"));
                    egui::ComboBox::from_id_salt("add_ship_faction")
                        .selected_text(&state.faction_id)
                        .show_ui(ui, |ui| {
                            for f in &factions {
                                ui.selectable_value(&mut state.faction_id, f.clone(), f);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Location"));
                    egui::ComboBox::from_id_salt("add_ship_location")
                        .selected_text(&state.location_name)
                        .show_ui(ui, |ui| {
                            for l in &locations {
                                ui.selectable_value(&mut state.location_name, l.clone(), l);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Credits"));
                    let mut credits = state.credits;
                    if ui
                        .add(
                            egui::DragValue::new(&mut credits)
                                .range(0..=10_000_000)
                                .speed(100.0),
                        )
                        .changed()
                    {
                        state.credits = credits;
                    }
                    ui.end_row();

                    ui.label(theme::caption("Name"));
                    ui.add(
                        egui::TextEdit::singleline(&mut state.name)
                            .hint_text("(auto-generated if empty)"),
                    );
                    ui.end_row();
                });

            ui.add_space(6.0);
            ui.horizontal(|ui| {
                if ui
                    .add(egui::Button::new(
                        egui::RichText::new("Spawn").color(theme::SUCCESS),
                    ))
                    .clicked()
                {
                    spawn_clicked = true;
                }
                if ui.button("Cancel").clicked() {
                    // Cancel just closes; we keep the form fields so
                    // the user can re-open and tweak without
                    // re-picking from scratch.
                    state.open = false;
                }
            });
        });

    if spawn_clicked {
        spawn_req.0 = Some(crate::sim::SpawnShipParams {
            class: state.class.clone(),
            faction_id: state.faction_id.clone(),
            location_name: state.location_name.clone(),
            credits: state.credits,
            name: state.name.clone(),
        });
        // Auto-close on spawn so the user sees their new ship; they
        // can re-open if they want to spawn a few in a row.
        state.open = false;
    } else {
        state.open = open;
    }
}

/// State for the "Add Facility" admin dialog. Mirrors AddShipDialog
/// — form fields persist between openings.
#[derive(Resource)]
struct AddFacilityDialogState {
    open: bool,
    name: String,
    facility_type: String,
    body_id: String,
    faction_id: String,
    docking_capacity: u32,
    credits: i64,
}

impl Default for AddFacilityDialogState {
    fn default() -> Self {
        Self {
            open: false,
            name: String::new(),
            facility_type: "station".to_string(),
            body_id: "earth".to_string(),
            faction_id: "independent".to_string(),
            docking_capacity: 4,
            credits: 10_000,
        }
    }
}

const FACILITY_TYPES: &[&str] = &[
    "station",
    "outpost",
    "mining_rig",
    "refinery",
    "factory",
    "farm",
    "shipyard",
];

fn add_facility_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<AddFacilityDialogState>,
    sim: Res<Sim>,
    mut spawn_req: ResMut<crate::sim::SpawnFacilityRequest>,
) {
    if !state.open {
        return;
    }

    use sim_core::agents::celestial_body::BodyIdentity;

    let mut factions: Vec<String> = sim.store.faction_by_id.keys().cloned().collect();
    factions.sort();

    let body_set: std::collections::BTreeSet<String> = sim
        .store
        .world
        .query::<&BodyIdentity>()
        .iter()
        .map(|(_e, id)| id.body_id.clone())
        .collect();
    let bodies: Vec<String> = body_set.into_iter().collect();

    let mut open = state.open;
    let mut spawn_clicked = false;
    egui::Window::new("Add Facility")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            egui::Grid::new("add_fac_form")
                .num_columns(2)
                .spacing([12.0, 6.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Name"));
                    ui.add(
                        egui::TextEdit::singleline(&mut state.name)
                            .hint_text("e.g. Hyperion Outpost"),
                    );
                    ui.end_row();

                    ui.label(theme::caption("Type"));
                    egui::ComboBox::from_id_salt("add_fac_type")
                        .selected_text(&state.facility_type)
                        .show_ui(ui, |ui| {
                            for &t in FACILITY_TYPES {
                                ui.selectable_value(&mut state.facility_type, t.to_string(), t);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Body"));
                    egui::ComboBox::from_id_salt("add_fac_body")
                        .selected_text(&state.body_id)
                        .show_ui(ui, |ui| {
                            for b in &bodies {
                                ui.selectable_value(&mut state.body_id, b.clone(), b);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Faction"));
                    egui::ComboBox::from_id_salt("add_fac_faction")
                        .selected_text(&state.faction_id)
                        .show_ui(ui, |ui| {
                            for f in &factions {
                                ui.selectable_value(&mut state.faction_id, f.clone(), f);
                            }
                        });
                    ui.end_row();

                    ui.label(theme::caption("Dock cap"));
                    let mut cap = state.docking_capacity as i32;
                    if ui
                        .add(egui::DragValue::new(&mut cap).range(0..=200).speed(1.0))
                        .changed()
                    {
                        state.docking_capacity = cap.max(0) as u32;
                    }
                    ui.end_row();

                    ui.label(theme::caption("Credits"));
                    let mut credits = state.credits;
                    if ui
                        .add(
                            egui::DragValue::new(&mut credits)
                                .range(0..=10_000_000)
                                .speed(100.0),
                        )
                        .changed()
                    {
                        state.credits = credits;
                    }
                    ui.end_row();
                });

            ui.add_space(6.0);
            ui.horizontal(|ui| {
                let valid = !state.name.trim().is_empty();
                let spawn_btn = ui.add_enabled(
                    valid,
                    egui::Button::new(egui::RichText::new("Spawn").color(theme::SUCCESS)),
                );
                if spawn_btn.clicked() {
                    spawn_clicked = true;
                }
                if !valid {
                    ui.label(
                        egui::RichText::new("name required")
                            .small()
                            .color(theme::WARN),
                    );
                }
                if ui.button("Cancel").clicked() {
                    state.open = false;
                }
            });
        });

    if spawn_clicked {
        spawn_req.0 = Some(crate::sim::SpawnFacilityParams {
            name: state.name.clone(),
            facility_type: state.facility_type.clone(),
            body_id: state.body_id.clone(),
            faction_id: state.faction_id.clone(),
            docking_capacity: state.docking_capacity,
            credits: state.credits,
        });
        state.open = false;
    } else {
        state.open = open;
    }
}

/// Main menu screen. Renders only when `AppState::MainMenu` is
/// active. The 3D backdrop (starfield + nebulas + bodies) keeps
/// drawing because RenderPlugin systems run unconditionally — the
/// title floats over the live galaxy. Buttons:
/// - **Start** transitions to InGame, unfreezes the sim.
/// - **Load Game** opens the save-list browser.
/// - **Options** opens the same OptionsState window the pause menu
///   uses, so audio mix is shared between menu and play.
/// - **Quit** sends `AppExit::Success`.
fn main_menu_panel(
    mut ctx: EguiContexts,
    mut new_universe: ResMut<NewUniverseDialogState>,
    mut options: ResMut<OptionsState>,
    mut saves: ResMut<SaveListState>,
    mut exit: EventWriter<AppExit>,
) {
    // Suppress the menu while any modal is up. Menu used Foreground
    // ordering so its buttons stayed visible above the 3D backdrop
    // — but Foreground also paints OVER egui Windows, which made
    // the button text bleed through Saves / Options / new-universe
    // modals. Cleanest fix: just don't draw the menu while a modal
    // is open.
    if new_universe.open || options.open || saves.open {
        return;
    }
    egui::Area::new(egui::Id::new("main_menu"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx.ctx_mut(), |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new("The Space Project")
                        .size(32.0)
                        .strong()
                        .color(theme::PRIMARY),
                );
                ui.add_space(28.0);

                let btn_size = egui::vec2(260.0, 40.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(
                            egui::RichText::new("Start")
                                .size(16.0)
                                .color(theme::PRIMARY),
                        ),
                    )
                    .clicked()
                {
                    new_universe.open = true;
                    new_universe.name = "sim".to_string();
                    new_universe.focus_pending = true;
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Load Game"))
                    .on_hover_text("Browse the saves stored next to the binary.")
                    .clicked()
                {
                    saves.open = true;
                    saves.last_scan = None; // force refresh on open
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Options"))
                    .clicked()
                {
                    options.open = true;
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(egui::RichText::new("Quit").color(theme::DANGER)),
                    )
                    .clicked()
                {
                    exit.send(AppExit::Success);
                }
                ui.add_space(20.0);
                credits_block(ui);
                ui.add_space(8.0);
            });
        });
}

/// Shared credit + version footer rendered on both the main menu
/// and the pause menu. CARGO_PKG_VERSION is the workspace version
/// from `Cargo.toml`; the Makefile reads the same field so packaged
/// builds (Info.plist, butler --userversion, archive names) line
/// up with what's shown in-game.
pub(super) fn credits_block(ui: &mut egui::Ui) {
    ui.label(
        egui::RichText::new(format!("v{}", env!("CARGO_PKG_VERSION")))
            .small()
            .monospace()
            .color(theme::TEXT_DIM),
    );
    ui.add_space(2.0);
    ui.label(
        egui::RichText::new("By Kalcode & Claude")
            .small()
            .color(theme::TEXT_DIM),
    );
    ui.label(
        egui::RichText::new("Made with ❤️ in Illinois")
            .small()
            .color(theme::TEXT_DIM),
    );
}

/// Modal that appears after Start. User picks a universe name; the
/// sanitised form becomes the SQLite file (`<name>.db`) loaded on
/// `OnEnter(InGame)`. Empty input falls back to `sim`. If a DB with
/// the chosen name already exists, the loader resumes it; otherwise
/// the seeder creates a fresh world.
#[derive(Resource)]
struct NewUniverseDialogState {
    open: bool,
    name: String,
    /// One-shot flag set when the dialog opens so we can grab the
    /// text-field focus on the first frame it renders. Cleared after
    /// the focus call lands.
    focus_pending: bool,
}

impl Default for NewUniverseDialogState {
    fn default() -> Self {
        Self {
            open: false,
            name: "sim".to_string(),
            focus_pending: false,
        }
    }
}

/// Strip everything that isn't `[A-Za-z0-9_-]` and clamp length so
/// the resulting `.db` path can't break out of its parent directory
/// or trip filesystem rules. Empty input → "sim" as the fallback.
fn sanitize_universe_name(raw: &str) -> String {
    let cleaned: String = raw
        .trim()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
        .take(48)
        .collect();
    if cleaned.is_empty() {
        "sim".to_string()
    } else {
        cleaned
    }
}

/// Directory where save DBs live (next to the running binary —
/// matches `scan_saves()` / `process_save_as()`). Falls back to the
/// current working directory if `current_exe` can't resolve, which
/// is the same fallback `resolve_db_path` uses for the default DB.
fn save_dir() -> std::path::PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| std::path::PathBuf::from("."))
}

/// Pick a free filename for a fresh universe — avoids clobbering
/// existing saves when the user hits Start with a name that already
/// has a `.db` on disk. Returns `(final_stem, path)`. If the base
/// name is free, returns it as-is. Otherwise appends `-2`, `-3`, …
/// up to a sanity cap.
fn unique_universe_path(stem: &str) -> (String, std::path::PathBuf) {
    let dir = save_dir();
    let base_path = dir.join(format!("{stem}.db"));
    if !base_path.exists() {
        return (stem.to_string(), base_path);
    }
    for n in 2..=999 {
        let candidate_stem = format!("{stem}-{n}");
        let candidate = dir.join(format!("{candidate_stem}.db"));
        if !candidate.exists() {
            return (candidate_stem, candidate);
        }
    }
    // Pathological case — 999 worlds with the same base name. Fall
    // back to a wall-clock suffix so we still produce a unique
    // path instead of clobbering.
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let suffix_stem = format!("{stem}-{ts}");
    let path = dir.join(format!("{suffix_stem}.db"));
    (suffix_stem, path)
}

fn new_universe_dialog(
    mut ctx: EguiContexts,
    mut state: ResMut<NewUniverseDialogState>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut sim: ResMut<Sim>,
    mut selected_save: ResMut<crate::sim::SelectedSavePath>,
) {
    if !state.open {
        return;
    }

    let mut want_start = false;
    let mut want_cancel = false;

    egui::Window::new("Name your universe")
        .id(egui::Id::new("new_universe_dialog"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(380.0)
        .show(ctx.ctx_mut(), |ui| {
            ui.add_space(4.0);
            ui.label(
                egui::RichText::new(
                    "Pick a name for this universe. The simulation \
                     persists to a SQLite file with this name. Letters, \
                     digits, dashes and underscores only.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
            ui.add_space(8.0);

            let resp = ui.add(
                egui::TextEdit::singleline(&mut state.name)
                    .hint_text("sim")
                    .desired_width(f32::INFINITY),
            );
            if state.focus_pending {
                resp.request_focus();
                state.focus_pending = false;
            }
            // Enter inside the text field commits.
            if resp.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                want_start = true;
            }

            let sanitized = sanitize_universe_name(&state.name);
            let (resolved_stem, _) = unique_universe_path(&sanitized);
            let collided = resolved_stem != sanitized;
            ui.add_space(2.0);
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new("File:").small().color(theme::TEXT_DIM));
                ui.label(
                    egui::RichText::new(format!("{resolved_stem}.db"))
                        .small()
                        .monospace()
                        .color(theme::PRIMARY),
                );
            });
            if collided {
                // Existing save with the picked stem — explain why
                // we're appending a suffix so the user isn't
                // surprised that the filename doesn't match what
                // they typed. They can either accept the new name
                // or hit Cancel and use Load Game on the existing
                // save instead.
                ui.label(
                    egui::RichText::new(format!(
                        "⚠ '{sanitized}.db' already exists — \
                         starting as '{resolved_stem}.db'. Use Load \
                         Game to resume the existing save."
                    ))
                    .small()
                    .color(theme::WARN),
                );
            }

            ui.add_space(10.0);
            ui.horizontal(|ui| {
                if ui
                    .add(egui::Button::new(
                        egui::RichText::new("Start").color(theme::PRIMARY),
                    ))
                    .clicked()
                {
                    want_start = true;
                }
                if ui.button("Cancel").clicked() {
                    want_cancel = true;
                }
            });
            // Esc cancels.
            if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                want_cancel = true;
            }
        });

    if want_cancel {
        state.open = false;
        return;
    }

    if want_start {
        let sanitized = sanitize_universe_name(&state.name);
        // Resolve to a non-colliding path so Start always means
        // "fresh world" — never silently overwrite or resume an
        // existing save. Resume goes through Load Game instead.
        let (final_stem, path) = unique_universe_path(&sanitized);
        info!(
            "client_bevy: starting universe '{}' → {}",
            final_stem,
            path.display(),
        );
        selected_save.0 = Some(path);
        sim.running = true;
        next_state.set(crate::AppState::InGame);
        state.open = false;
    }
}

/// Save-list browser. Scans the directory containing the executable
/// (or current working directory in dev) for `*.db` files. The
/// active `sim.db` is included as a special "Current session" entry
/// — loadable (re-loads the live DB) but not deletable so users
/// can't blow away their auto-saved game by accident. Save-As
/// snapshots show normally with Load + Delete.
#[derive(Resource, Default)]
struct SaveListState {
    open: bool,
    saves: Vec<SaveEntry>,
    /// `None` forces a re-scan on next render; otherwise we cache
    /// the listing so opening the panel doesn't hit the FS every
    /// frame. Refresh button bumps this back to None.
    last_scan: Option<std::time::Instant>,
}

#[derive(Clone)]
struct SaveEntry {
    path: std::path::PathBuf,
    name: String,
    modified_iso: String,
    size_kb: u64,
    /// True for the active `sim.db`. Renders with a "Current
    /// session" badge and disables the Delete button.
    is_active: bool,
}

fn scan_saves() -> Vec<SaveEntry> {
    let dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| std::path::PathBuf::from("."));
    let mut out: Vec<SaveEntry> = Vec::new();
    let Ok(rd) = std::fs::read_dir(&dir) else {
        return out;
    };
    for entry in rd.flatten() {
        let path = entry.path();
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if !name.ends_with(".db") {
            continue;
        }
        let is_active = name == "sim.db";
        let meta = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let size_kb = meta.len() / 1024;
        let modified_iso = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| {
                let secs = d.as_secs() as i64;
                // Compact YYYY-MM-DD HH:MM via chrono-free math.
                let days = secs / 86_400;
                let h = (secs % 86_400) / 3600;
                let m = (secs % 3600) / 60;
                // Naive UTC; plenty for a filesystem timestamp display.
                let (y, mo, d) = days_to_ymd(days);
                format!("{y:04}-{mo:02}-{d:02} {h:02}:{m:02}")
            })
            .unwrap_or_else(|| "?".to_string());
        out.push(SaveEntry {
            path,
            name,
            modified_iso,
            size_kb,
            is_active,
        });
    }
    // Active session always pinned to the top, then snapshots
    // newest-first.
    out.sort_by(|a, b| {
        b.is_active
            .cmp(&a.is_active)
            .then_with(|| b.modified_iso.cmp(&a.modified_iso))
    });
    out
}

/// Convert days-since-1970-01-01 to (year, month, day). Naive
/// proleptic Gregorian — the chrono crate would be cleaner but
/// adding a dep for one display string is overkill.
fn days_to_ymd(mut days: i64) -> (i32, u32, u32) {
    let mut y: i32 = 1970;
    loop {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        let yd: i64 = if leap { 366 } else { 365 };
        if days < yd {
            break;
        }
        days -= yd;
        y += 1;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let mdays: [i64; 12] = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut m: usize = 0;
    while m < 12 && days >= mdays[m] {
        days -= mdays[m];
        m += 1;
    }
    (y, (m + 1) as u32, (days + 1) as u32)
}

fn save_list_panel(
    mut ctx: EguiContexts,
    mut state: ResMut<SaveListState>,
    mut selected_save: ResMut<crate::sim::SelectedSavePath>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut sim: ResMut<Sim>,
) {
    if !state.open {
        return;
    }

    // Scan once per open (or after Refresh). FS dirs change rarely
    // during play so caching is fine; the user can hit Refresh to
    // re-scan after a Save-As.
    if state.last_scan.is_none() {
        state.saves = scan_saves();
        state.last_scan = Some(std::time::Instant::now());
    }

    let mut open = state.open;
    let mut want_refresh = false;
    let mut want_delete: Option<std::path::PathBuf> = None;
    let mut want_load: Option<std::path::PathBuf> = None;

    egui::Window::new("Saves")
        .id(egui::Id::new("save_list_window"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(540.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label(theme::section_header("Save snapshots"));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.small_button("Refresh").clicked() {
                        want_refresh = true;
                    }
                });
            });
            ui.separator();
            if state.saves.is_empty() {
                ui.label(
                    egui::RichText::new(
                        "No save files found next to the binary. \
                         Start a new game to create one, or use Save As… \
                         from the pause menu to take a snapshot.",
                    )
                    .italics()
                    .color(theme::TEXT_DIM),
                );
                return;
            }
            egui::ScrollArea::vertical()
                .max_height(400.0)
                .show(ui, |ui| {
                    egui::Grid::new("save_list_grid")
                        .num_columns(4)
                        .striped(true)
                        .spacing([12.0, 4.0])
                        .show(ui, |ui| {
                            ui.label(theme::caption("Name"));
                            ui.label(theme::caption("Modified"));
                            ui.label(theme::caption("Size"));
                            ui.label("");
                            ui.end_row();
                            for save in &state.saves {
                                if save.is_active {
                                    ui.horizontal(|ui| {
                                        ui.label(&save.name);
                                        ui.label(
                                            egui::RichText::new("· Current session")
                                                .small()
                                                .color(theme::PRIMARY),
                                        );
                                    });
                                } else {
                                    ui.label(&save.name);
                                }
                                ui.label(
                                    egui::RichText::new(&save.modified_iso)
                                        .small()
                                        .monospace()
                                        .color(theme::TEXT_DIM),
                                );
                                ui.label(
                                    egui::RichText::new(format!("{} KB", save.size_kb))
                                        .small()
                                        .monospace(),
                                );
                                ui.horizontal(|ui| {
                                    if ui
                                        .small_button("Load")
                                        .on_hover_text(if save.is_active {
                                            "Load the active session DB."
                                        } else {
                                            "Load this Save-As snapshot."
                                        })
                                        .clicked()
                                    {
                                        want_load = Some(save.path.clone());
                                    }
                                    // sim.db is safe to delete from the
                                    // main menu — load_world only opens
                                    // a pool on OnEnter(InGame), so no
                                    // file handle is held here. Next
                                    // Start will recreate + seed a
                                    // fresh world.
                                    let delete_hover = if save.is_active {
                                        "Permanently delete the active save. \
                                         The next Start will create a fresh \
                                         seeded world."
                                    } else {
                                        "Permanently delete this snapshot \
                                         from disk. No confirmation."
                                    };
                                    if ui
                                        .small_button(
                                            egui::RichText::new("Delete").color(theme::DANGER),
                                        )
                                        .on_hover_text(delete_hover)
                                        .clicked()
                                    {
                                        want_delete = Some(save.path.clone());
                                    }
                                });
                                ui.end_row();
                            }
                        });
                });
        });

    if want_refresh {
        state.last_scan = None;
    }
    if let Some(p) = want_delete {
        match std::fs::remove_file(&p) {
            Ok(()) => {
                info!("client_bevy: deleted save {}", p.display());
                // Sidecar WAL/SHM files would otherwise resurrect
                // partial state on next open. Best-effort cleanup —
                // missing sidecars (the common case for a clean DB)
                // are silently ignored.
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    if let Some(parent) = p.parent() {
                        for suffix in ["-wal", "-shm", "-journal"] {
                            let side = parent.join(format!("{name}{suffix}"));
                            let _ = std::fs::remove_file(&side);
                        }
                    }
                }
                state.last_scan = None;
            }
            Err(e) => {
                error!("client_bevy: failed to delete {}: {}", p.display(), e);
            }
        }
    }
    if let Some(p) = want_load {
        info!("client_bevy: loading save {}", p.display());
        // Plumb through to the sim's OnEnter(InGame) load — set the
        // path, transition state, then close the panel. The early
        // return below skips the `state.open = open` writeback that
        // would otherwise restore the open flag from egui's
        // close-button binding (which is still `true` at this point
        // because the user clicked Load, not X).
        selected_save.0 = Some(p);
        sim.running = true;
        next_state.set(crate::AppState::InGame);
        state.open = false;
        return;
    }
    state.open = open;
}

