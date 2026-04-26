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
mod context;
mod contracts;
mod events;
mod facility;
mod factions;
mod format;
mod help;
mod icons;
mod labels;
mod lifecycle;
mod markets;
mod menus;
mod minimap;
mod panel_stack;
mod populations;
mod retirements;
mod ship_details;
mod ship_list;
mod spawn_dialogs;
mod theme;

use construction::{construction_panel, ConstructionState};
pub use context::{ContextMenuRequest, ContextMenuTarget};
use context::context_menu;
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
use lifecycle::{
    main_menu_panel, new_universe_dialog, save_list_panel, NewUniverseDialogState, SaveListState,
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
use spawn_dialogs::{
    add_facility_dialog, add_ship_dialog, AddFacilityDialogState, AddShipDialogState,
};

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


