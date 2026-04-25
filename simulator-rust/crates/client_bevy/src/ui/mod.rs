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

use crate::camera::{CameraFocusRequest, CameraResetRequest, OrbitCamera};
use crate::render::SCALE_FACTOR;
use crate::sim::{EventsLog, PhasePerf, Retirements, Sim, TickPerf};

mod icons;
mod theme;

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
            .init_resource::<AddShipDialogState>()
            .init_resource::<AddFacilityDialogState>()
            .init_resource::<ContextMenuRequest>()
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
                    keyboard_shortcuts,
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
            let mut speed = sim.tick_mult.max(1);
            egui::ComboBox::from_id_salt("sim_speed_combo")
                .selected_text(format!("{}×", speed))
                .show_ui(ui, |ui| {
                    for &s in &[1u32, 2, 4, 8] {
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
                    "Sim speed multiplier — tick_sim runs the tick body N× per \
                     FixedUpdate. Higher = faster game time at the cost of frame \
                     budget. 1× ≈ 8 ticks/sec real-time, 8× ≈ 64 ticks/sec.",
                );
            ui.separator();
            ui.label(
                egui::RichText::new(format!("tick {}", sim.tick))
                    .monospace()
                    .color(theme::TEXT_DIM),
            )
            .on_hover_text(
                "Current sim tick. Each tick advances all agents one step \
                 (planner, market, facility, etc). Default cadence is \
                 8 ticks/sec × tick_mult.",
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
                icons::ledger(),
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
                icons::ledger(),
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

// =============================================================================
// Ship list panel
// =============================================================================

/// Persistent UI state for the ship list (sort key, search filter,
/// whether the window is open). Anything that needs to survive
/// between frames lives on this Resource.
#[derive(Resource)]
struct ShipListState {
    open: bool,
    sort: ShipSort,
    descending: bool,
    filter: String,
}

impl Default for ShipListState {
    fn default() -> Self {
        // CLIENT_BEVY_OPEN_PANELS=ships|all auto-opens this panel
        // on boot — used by the visual-loop screenshot path so the
        // panel is visible at the auto-screenshot frame without
        // simulating a click.
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("ships") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: ShipSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ShipSort {
    #[default]
    Name,
    Class,
    Faction,
    Location,
}

/// One egui row worth of ship data, extracted from the hecs world
/// once per frame. Keeps the render loop's query work bounded — we
/// iterate hecs once, build a Vec, sort, then render.
struct ShipRow {
    id: String,
    name: String,
    class: String,
    faction: String,
    location: String,
    // Hover-tooltip fields. Read every frame for every ship — at
    // 1604 ships × 3 numeric pulls each that's 4800 hash lookups,
    // trivial vs the rest of UI cost.
    credits: i64,
    fuel_frac: f32,
    goal: String,
}

/// Currently-selected ship, written by a click in the ship list and
/// read by the details panel. `None` means no selection (details
/// window closes itself). Public so the render layer can use it to
/// highlight the matching Bevy entity.
#[derive(Resource, Default)]
pub struct SelectedShip(pub Option<String>);

fn ship_list(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ShipListState>,
    mut selected: ResMut<SelectedShip>,
) {
    use sim_core::agents::ship::{ShipAI, ShipEconomy, ShipFuel, ShipIdentity, ShipPosition};

    // Snapshot the mutable fields we'll need inside egui closures so
    // the borrow checker doesn't choke on overlapping mut refs into
    // the ResMut. We write back at the end of the function.
    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    let rows: Vec<ShipRow> = sim
        .store
        .world
        .query::<(
            &ShipIdentity,
            &ShipPosition,
            &ShipEconomy,
            &ShipFuel,
            &ShipAI,
        )>()
        .iter()
        .map(|(_e, (id, pos, econ, fuel, ai))| ShipRow {
            id: id.id.clone(),
            name: id.name.clone(),
            class: id.class.clone(),
            faction: id.faction_id.clone(),
            location: pos
                .location_name
                .clone()
                .unwrap_or_else(|| "(in transit)".into()),
            credits: econ.credits,
            fuel_frac: fuel.fraction(),
            goal: ai.current_goal.clone(),
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&ShipRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            ShipSort::Name => a.name.cmp(&b.name),
            ShipSort::Class => a.class.cmp(&b.class),
            ShipSort::Faction => a.faction.cmp(&b.faction),
            ShipSort::Location => a.location.cmp(&b.location),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let shown = filtered.len();
    let total = rows.len();
    // Use ScrollArea + rows cap so 1600-entry worlds stay responsive.
    // egui handles its own virtualisation via `show_rows`; we cap to
    // PAGE_SIZE upfront so sort work doesn't blow up on pathological
    // filters. 500 is plenty for typical play.
    const PAGE_SIZE: usize = 500;
    let page: Vec<&ShipRow> = filtered.into_iter().take(PAGE_SIZE).collect();

    egui::Window::new(format!("Ships · {shown}/{total}"))
        .id(egui::Id::new("ships_window"))
        .default_width(640.0)
        .default_height(400.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
                if shown > PAGE_SIZE {
                    ui.label(
                        egui::RichText::new(format!("(top {} shown)", PAGE_SIZE))
                            .small()
                            .color(theme::TEXT_DIM),
                    );
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("ship_list_grid")
                    .striped(true)
                    .num_columns(7)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        sort_header(ui, "Name", &mut sort, &mut descending, ShipSort::Name);
                        sort_header(ui, "Class", &mut sort, &mut descending, ShipSort::Class);
                        sort_header(ui, "Faction", &mut sort, &mut descending, ShipSort::Faction);
                        sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            ShipSort::Location,
                        );
                        // Goal / Fuel / Credits aren't sortable yet —
                        // keep header styling consistent so the row
                        // reads as a single header band.
                        ui.label(egui::RichText::new("Goal").strong().color(theme::TEXT_DIM));
                        ui.label(egui::RichText::new("Fuel").strong().color(theme::TEXT_DIM));
                        ui.label(
                            egui::RichText::new("Credits")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ui.end_row();

                        for row in &page {
                            // Name cell doubles as the row selector —
                            // clicking highlights and opens the details
                            // panel on this ship.
                            let is_sel = selected.0.as_deref() == Some(row.id.as_str());
                            if ui.selectable_label(is_sel, &row.name).clicked() {
                                selected.0 = Some(row.id.clone());
                            }
                            ui.label(egui::RichText::new(&row.class).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&row.faction).color(theme::TEXT_DIM));
                            // Location: italicise "(in transit)" so a
                            // moving ship reads differently from a
                            // docked one without colour-shouting it.
                            if row.location == "(in transit)" {
                                ui.label(
                                    egui::RichText::new(&row.location)
                                        .italics()
                                        .color(theme::TEXT_DIM),
                                );
                            } else {
                                ui.label(&row.location);
                            }
                            // Goal is the planner's current goal name,
                            // monospaced so list lines up.
                            ui.label(egui::RichText::new(&row.goal).small().monospace());
                            // Fuel %: SUCCESS ≥ 50%, WARN ≥ 20%,
                            // DANGER below — same banding the Godot
                            // ship_list uses (theme_palette colours).
                            let fuel_pct = row.fuel_frac * 100.0;
                            ui.colored_label(
                                theme::status_color(fuel_pct, (50.0, 20.0)),
                                format!("{fuel_pct:.0}%"),
                            );
                            // Credits: thousands-separated for
                            // readability at typical 1k-100k+ range.
                            ui.label(egui::RichText::new(format_credits(row.credits)).monospace());
                            ui.end_row();
                        }
                    });
            });
        });

    // Write the local snapshot back to the Resource for next frame.
    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut ShipSort,
    descending: &mut bool,
    target: ShipSort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    // Frameless so the header row reads as a single band rather
    // than a row of boxed buttons. Active sort gets PRIMARY tint;
    // others use TEXT_DIM so the active column stands out.
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            *descending = false;
        }
    }
}

// =============================================================================
// Contracts panel
// =============================================================================

#[derive(Resource)]
struct ContractsState {
    open: bool,
    kind_filter: ContractKindFilter,
    status_filter: ContractStatusFilter,
    show_expired: bool,
}

impl Default for ContractsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("contracts") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            kind_filter: ContractKindFilter::default(),
            status_filter: ContractStatusFilter::default(),
            show_expired: false,
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ContractKindFilter {
    #[default]
    All,
    Delivery,
    Courier,
    Passenger,
    Subsidy,
    Supply,
    CrewMission,
    Construction,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum ContractStatusFilter {
    #[default]
    All,
    Posted,
    Accepted,
    PickedUp,
    Delivered,
    Paid,
    Expired,
}

fn contracts_panel(mut ctx: EguiContexts, sim: Res<Sim>, mut state: ResMut<ContractsState>) {
    use sim_core::economy::contracts::{ContractStatus, ContractType};

    let mut open = state.open;
    let mut kind_filter = state.kind_filter;
    let mut status_filter = state.status_filter;
    let mut show_expired = state.show_expired;

    if !open {
        return;
    }

    // Build the view slice. We walk the board once and filter upfront
    // so the render loop doesn't re-check predicates per row. At 500+
    // contracts the full walk is trivial.
    struct Row {
        id: String,
        kind: &'static str,
        status: &'static str,
        commodity: String,
        quantity: u32,
        source: String,
        dest: String,
        payment: i64,
        faction: String,
        min_rep: u8,
    }
    let rows: Vec<Row> = sim
        .store
        .contracts
        .iter()
        .filter(|c| match kind_filter {
            ContractKindFilter::All => true,
            ContractKindFilter::Delivery => matches!(c.contract_type, ContractType::Delivery),
            ContractKindFilter::Courier => matches!(c.contract_type, ContractType::Courier),
            ContractKindFilter::Passenger => matches!(c.contract_type, ContractType::Passenger),
            ContractKindFilter::Subsidy => matches!(c.contract_type, ContractType::Subsidy),
            ContractKindFilter::Supply => matches!(c.contract_type, ContractType::Supply),
            ContractKindFilter::CrewMission => {
                matches!(c.contract_type, ContractType::CrewMission)
            }
            ContractKindFilter::Construction => {
                matches!(c.contract_type, ContractType::Construction)
            }
        })
        .filter(|c| match status_filter {
            ContractStatusFilter::All => true,
            ContractStatusFilter::Posted => matches!(c.status, ContractStatus::Posted),
            ContractStatusFilter::Accepted => matches!(c.status, ContractStatus::Accepted),
            ContractStatusFilter::PickedUp => matches!(c.status, ContractStatus::PickedUp),
            ContractStatusFilter::Delivered => matches!(c.status, ContractStatus::Delivered),
            ContractStatusFilter::Paid => matches!(c.status, ContractStatus::Paid),
            ContractStatusFilter::Expired => matches!(c.status, ContractStatus::Expired),
        })
        .filter(|c| show_expired || !matches!(c.status, ContractStatus::Expired))
        .map(|c| Row {
            id: c.id.clone(),
            kind: c.contract_type.as_str(),
            status: status_str(&c.status),
            commodity: c.commodity.as_str().to_string(),
            quantity: c.quantity,
            source: c.source_location.clone(),
            dest: c.destination_location.clone(),
            payment: c.payment,
            faction: c.faction_id.clone().unwrap_or_default(),
            min_rep: c.min_reputation,
        })
        .collect();

    let total = sim.store.contracts.iter().count();
    let shown = rows.len();

    egui::Window::new(format!("Contracts · {shown}/{total}"))
        .id(egui::Id::new("contracts_window"))
        .default_width(820.0)
        .default_height(440.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("kind:");
                kind_combo(ui, &mut kind_filter);
                ui.separator();
                ui.label("status:");
                status_combo(ui, &mut status_filter);
                ui.separator();
                ui.checkbox(&mut show_expired, "show expired");
            });
            ui.separator();

            const PAGE_SIZE: usize = 400;
            let page_rows: Vec<&Row> = rows.iter().take(PAGE_SIZE).collect();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("contracts_grid")
                    .striped(true)
                    .num_columns(10)
                    .spacing([10.0, 3.0])
                    .show(ui, |ui| {
                        // Headers — Source / Dest are separate columns
                        // so the egui default font's missing "→" glyph
                        // (rendered as a tofu box) doesn't show up.
                        for header in [
                            "Kind", "Status", "Item", "Qty", "Source", "Dest", "Pay", "Faction",
                            "Rep", "ID",
                        ] {
                            ui.label(egui::RichText::new(header).strong().color(theme::TEXT_DIM));
                        }
                        ui.end_row();

                        for r in &page_rows {
                            ui.label(r.kind);
                            ui.colored_label(contract_status_color(r.status), r.status);
                            ui.label(egui::RichText::new(&r.commodity).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(format!("{}", r.quantity)).monospace());
                            // Source dimmed; destination is what the
                            // eye usually wants on this row.
                            ui.label(egui::RichText::new(&r.source).color(theme::TEXT_DIM));
                            ui.label(&r.dest);
                            // Pay in monospace, abbreviated (1.2k / 3.4M)
                            ui.label(egui::RichText::new(format_credits(r.payment)).monospace());
                            ui.label(egui::RichText::new(&r.faction).color(theme::TEXT_DIM));
                            // Rep gate: PRIMARY when set, dim em-dash
                            // when unrestricted (public board).
                            if r.min_rep > 0 {
                                ui.colored_label(theme::PRIMARY, format!("{}", r.min_rep));
                            } else {
                                ui.label(egui::RichText::new("-").color(theme::TEXT_DIM));
                            }
                            ui.label(
                                egui::RichText::new(&r.id)
                                    .small()
                                    .monospace()
                                    .color(theme::TEXT_DIM),
                            );
                            ui.end_row();
                        }
                    });
            });
            if shown > PAGE_SIZE {
                ui.separator();
                ui.label(
                    egui::RichText::new(format!(
                        "{} more contracts past page cap",
                        shown - PAGE_SIZE
                    ))
                    .small()
                    .color(theme::TEXT_DIM),
                );
            }
        });

    state.open = open;
    state.kind_filter = kind_filter;
    state.status_filter = status_filter;
    state.show_expired = show_expired;
}

fn status_str(s: &sim_core::economy::contracts::ContractStatus) -> &'static str {
    use sim_core::economy::contracts::ContractStatus as S;
    match s {
        S::Posted => "posted",
        S::Accepted => "accepted",
        S::PickedUp => "picked_up",
        S::Delivered => "delivered",
        S::Paid => "paid",
        S::Expired => "expired",
    }
}

/// Map a contract status string to a theme palette colour. Posted
/// = PRIMARY (info), in-flight (accepted/picked_up) = WARN, terminal
/// success (delivered/paid) = SUCCESS, terminal failure (expired) =
/// DANGER. Renamed from `status_color` to avoid colliding with
/// `theme::status_color`, which is the threshold-based helper.
fn contract_status_color(s: &'static str) -> egui::Color32 {
    match s {
        "posted" => theme::PRIMARY,
        "accepted" | "picked_up" => theme::WARN,
        "delivered" | "paid" => theme::SUCCESS,
        "expired" => theme::DANGER,
        _ => theme::TEXT,
    }
}

fn kind_combo(ui: &mut egui::Ui, current: &mut ContractKindFilter) {
    egui::ComboBox::from_id_salt("kind_filter_combo")
        .selected_text(match current {
            ContractKindFilter::All => "all",
            ContractKindFilter::Delivery => "delivery",
            ContractKindFilter::Courier => "courier",
            ContractKindFilter::Passenger => "passenger",
            ContractKindFilter::Subsidy => "subsidy",
            ContractKindFilter::Supply => "supply",
            ContractKindFilter::CrewMission => "crew_mission",
            ContractKindFilter::Construction => "construction",
        })
        .show_ui(ui, |ui| {
            for (label, value) in [
                ("all", ContractKindFilter::All),
                ("delivery", ContractKindFilter::Delivery),
                ("courier", ContractKindFilter::Courier),
                ("passenger", ContractKindFilter::Passenger),
                ("subsidy", ContractKindFilter::Subsidy),
                ("supply", ContractKindFilter::Supply),
                ("crew_mission", ContractKindFilter::CrewMission),
                ("construction", ContractKindFilter::Construction),
            ] {
                ui.selectable_value(current, value, label);
            }
        });
}

fn status_combo(ui: &mut egui::Ui, current: &mut ContractStatusFilter) {
    egui::ComboBox::from_id_salt("status_filter_combo")
        .selected_text(match current {
            ContractStatusFilter::All => "all",
            ContractStatusFilter::Posted => "posted",
            ContractStatusFilter::Accepted => "accepted",
            ContractStatusFilter::PickedUp => "picked_up",
            ContractStatusFilter::Delivered => "delivered",
            ContractStatusFilter::Paid => "paid",
            ContractStatusFilter::Expired => "expired",
        })
        .show_ui(ui, |ui| {
            for (label, value) in [
                ("all", ContractStatusFilter::All),
                ("posted", ContractStatusFilter::Posted),
                ("accepted", ContractStatusFilter::Accepted),
                ("picked_up", ContractStatusFilter::PickedUp),
                ("delivered", ContractStatusFilter::Delivered),
                ("paid", ContractStatusFilter::Paid),
                ("expired", ContractStatusFilter::Expired),
            ] {
                ui.selectable_value(current, value, label);
            }
        });
}

// =============================================================================
// Factions panel
// =============================================================================
//
// Godot-parity faction ledger. Two sections in one window:
//   1. Per-faction ledger: treasury + ship count + facility count +
//      active subsidies + home system. Sortable by clicking headers.
//   2. Pairwise relations matrix: each (a,b) shows standing + treaty.
//      Matrix is small (≤8 factions → 28 pairs) so plain grid is fine.
//
// Reads `FactionData` components straight out of hecs, counts ships +
// facilities by iterating their identity components once per frame
// (tiny work at this scale).

#[derive(Resource)]
struct FactionsState {
    open: bool,
    sort: FactionSort,
    descending: bool,
}

impl Default for FactionsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("factions") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: FactionSort::default(),
            descending: false,
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FactionSort {
    #[default]
    Name,
    Treasury,
    Ships,
    Facilities,
    Subsidies,
}

struct FactionRow {
    name: String,
    home_system: String,
    faction_type: String,
    treasury: i64,
    ships: u32,
    facilities: u32,
    subsidies: u32,
}

fn factions_panel(mut ctx: EguiContexts, sim: Res<Sim>, mut state: ResMut<FactionsState>) {
    use sim_core::agents::{
        facility::FacilityIdentity, faction::FactionData, faction_relations::TreatyKind,
        ship::ShipIdentity,
    };
    use std::collections::HashMap;

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;

    if !open {
        return;
    }

    // Ship + facility counts per faction id, built once.
    let mut ship_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&ShipIdentity>().iter() {
        *ship_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }
    let mut fac_counts: HashMap<String, u32> = HashMap::new();
    for (_e, id) in sim.store.world.query::<&FacilityIdentity>().iter() {
        *fac_counts.entry(id.faction_id.clone()).or_insert(0) += 1;
    }

    let mut rows: Vec<FactionRow> = sim
        .store
        .world
        .query::<&FactionData>()
        .iter()
        .map(|(_e, f)| FactionRow {
            name: f.name.clone(),
            home_system: f.home_system.clone(),
            faction_type: f.faction_type.clone(),
            treasury: f.treasury,
            ships: ship_counts.get(&f.id).copied().unwrap_or(0),
            facilities: fac_counts.get(&f.id).copied().unwrap_or(0),
            subsidies: f.active_subsidies,
        })
        .collect();

    rows.sort_by(|a, b| {
        let cmp = match sort {
            FactionSort::Name => a.name.cmp(&b.name),
            FactionSort::Treasury => a.treasury.cmp(&b.treasury),
            FactionSort::Ships => a.ships.cmp(&b.ships),
            FactionSort::Facilities => a.facilities.cmp(&b.facilities),
            FactionSort::Subsidies => a.subsidies.cmp(&b.subsidies),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    egui::Window::new(format!("Factions · {}", rows.len()))
        .id(egui::Id::new("factions_window"))
        .default_width(720.0)
        .default_height(520.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.label(egui::RichText::new("Ledger").strong().color(theme::PRIMARY));
            egui::Grid::new("factions_ledger_grid")
                .striped(true)
                .num_columns(6)
                .spacing([12.0, 3.0])
                .show(ui, |ui| {
                    faction_sort_header(
                        ui,
                        "Faction",
                        &mut sort,
                        &mut descending,
                        FactionSort::Name,
                    );
                    ui.label(
                        egui::RichText::new("System")
                            .strong()
                            .color(theme::TEXT_DIM),
                    );
                    faction_sort_header(
                        ui,
                        "Treasury",
                        &mut sort,
                        &mut descending,
                        FactionSort::Treasury,
                    );
                    faction_sort_header(
                        ui,
                        "Ships",
                        &mut sort,
                        &mut descending,
                        FactionSort::Ships,
                    );
                    faction_sort_header(
                        ui,
                        "Fac",
                        &mut sort,
                        &mut descending,
                        FactionSort::Facilities,
                    );
                    faction_sort_header(
                        ui,
                        "Subs",
                        &mut sort,
                        &mut descending,
                        FactionSort::Subsidies,
                    );
                    ui.end_row();

                    for r in &rows {
                        // Faction name strong, type as small dim
                        // suffix so the row name stands out.
                        ui.horizontal(|ui| {
                            ui.label(egui::RichText::new(&r.name).strong());
                            ui.label(
                                egui::RichText::new(format!("({})", r.faction_type))
                                    .small()
                                    .color(theme::TEXT_DIM),
                            );
                        });
                        ui.label(egui::RichText::new(&r.home_system).color(theme::TEXT_DIM));
                        // Treasury banding via theme helper —
                        // SUCCESS ≥ 10k, WARN ≥ 2k, DANGER below.
                        // Mirrors the broke-strike threshold the
                        // sim uses for bailouts.
                        ui.colored_label(
                            theme::status_color(r.treasury as f32, (10_000.0, 2_000.0)),
                            egui::RichText::new(format_credits(r.treasury)).monospace(),
                        );
                        ui.label(egui::RichText::new(format!("{}", r.ships)).monospace());
                        ui.label(egui::RichText::new(format!("{}", r.facilities)).monospace());
                        ui.label(egui::RichText::new(format!("{}", r.subsidies)).monospace());
                        ui.end_row();
                    }
                });

            ui.separator();
            ui.label(
                egui::RichText::new("Relations")
                    .strong()
                    .color(theme::PRIMARY),
            );
            ui.label(
                egui::RichText::new("canonical pairs · standing in [-100, 100]")
                    .small()
                    .color(theme::TEXT_DIM),
            );

            egui::ScrollArea::vertical()
                .id_salt("relations_scroll")
                .max_height(240.0)
                .show(ui, |ui| {
                    egui::Grid::new("relations_grid")
                        .striped(true)
                        .num_columns(4)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            for header in ["A", "B", "Standing", "Treaty"] {
                                ui.label(
                                    egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                );
                            }
                            ui.end_row();

                            let mut pairs: Vec<_> = sim.store.relations.iter().collect();
                            pairs.sort_by(|(ka, _), (kb, _)| ka.cmp(kb));

                            for ((a, b), state) in pairs {
                                ui.label(egui::RichText::new(a).color(theme::TEXT_DIM));
                                ui.label(b);
                                // Standing: SUCCESS ≥ 25, neutral
                                // band TEXT, DANGER ≤ -25.
                                let s_color = if state.standing >= 25 {
                                    theme::SUCCESS
                                } else if state.standing <= -25 {
                                    theme::DANGER
                                } else {
                                    theme::TEXT
                                };
                                ui.colored_label(
                                    s_color,
                                    egui::RichText::new(format!("{:+}", state.standing))
                                        .monospace(),
                                );
                                // Treaty palette: Allied/TradePact
                                // green-on-cyan, Neutral text,
                                // Tense/Hostile/War warming reds.
                                let t_color = match state.treaty {
                                    TreatyKind::Allied => theme::PRIMARY,
                                    TreatyKind::TradePact => theme::SUCCESS,
                                    TreatyKind::Neutral => theme::TEXT_DIM,
                                    TreatyKind::Tense => theme::WARN,
                                    TreatyKind::Hostile | TreatyKind::War => theme::DANGER,
                                };
                                ui.colored_label(t_color, state.treaty.as_str());
                                ui.end_row();
                            }
                        });
                });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
}

fn faction_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FactionSort,
    descending: &mut bool,
    target: FactionSort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    // Mirror sort_header (ship list): PRIMARY tint when this column
    // is the active sort, TEXT_DIM otherwise; frameless button.
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Treasury / ships / facilities / subsidies default to
            // descending so "biggest first" feels natural; name
            // defaults to ascending (A→Z).
            *descending = !matches!(target, FactionSort::Name);
        }
    }
}

fn format_credits(n: i64) -> String {
    // Quick humanise so the ledger column isn't a wall of digits. Keeps
    // precision under 10k since that's where the interesting drift is.
    if n.abs() >= 1_000_000 {
        format!("{:.2}M", n as f64 / 1_000_000.0)
    } else if n.abs() >= 10_000 {
        format!("{:.1}k", n as f64 / 1_000.0)
    } else {
        format!("{}", n)
    }
}

// =============================================================================
// Markets panel
// =============================================================================
//
// One collapsing header per market location. Expanded view shows every
// commodity's price / supply / demand / shortage-tick counter. Top-level
// row badges the market as `crisis` (MARKET_CRISIS_SHORTAGE_TICKS hit
// on any commodity) or `short` (any commodity with shortage_ticks > 0).
// Filter narrows by location substring, and a toggle collapses normal
// markets so the eye goes straight to the problem spots.

#[derive(Resource)]
struct MarketsState {
    open: bool,
    filter: String,
    only_shortages: bool,
}

impl Default for MarketsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("markets") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            filter: String::new(),
            only_shortages: false,
        }
    }
}

fn markets_panel(mut ctx: EguiContexts, sim: Res<Sim>, mut state: ResMut<MarketsState>) {
    use sim_core::agents::market::{
        MarketHistory, MarketIdentity, MarketPricing, MARKET_CRISIS_SHORTAGE_TICKS,
    };
    use sim_core::economy::commodities::Commodity;

    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut only_shortages = state.only_shortages;

    if !open {
        return;
    }

    // Collect one view-model per market. We query all three components
    // per entity via `query_one` below to keep borrow rules simple; at
    // ~40 markets this is trivially cheap.
    struct MarketRow {
        location: String,
        prices: Vec<(Commodity, f32)>,
        supply: Vec<(Commodity, f32)>,
        demand: Vec<(Commodity, f32)>,
        shortage_ticks: Vec<(Commodity, u32)>,
        crisis: bool,
        any_short: bool,
    }

    let mut rows: Vec<MarketRow> = Vec::new();
    let entities: Vec<_> = sim
        .store
        .world
        .query::<&MarketIdentity>()
        .iter()
        .map(|(e, id)| (e, id.facility_location.clone()))
        .collect();
    for (entity, location) in entities {
        let pricing = sim
            .store
            .world
            .query_one::<&MarketPricing>(entity)
            .ok()
            .and_then(|mut q| q.get().cloned());
        let history = sim
            .store
            .world
            .query_one::<&MarketHistory>(entity)
            .ok()
            .and_then(|mut q| q.get().cloned());
        let (Some(pricing), Some(history)) = (pricing, history) else {
            continue;
        };

        let mut prices: Vec<(Commodity, f32)> =
            pricing.prices.iter().map(|(c, v)| (*c, *v)).collect();
        prices.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut supply: Vec<(Commodity, f32)> =
            pricing.supply.iter().map(|(c, v)| (*c, *v)).collect();
        supply.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut demand: Vec<(Commodity, f32)> =
            pricing.demand.iter().map(|(c, v)| (*c, *v)).collect();
        demand.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
        let mut shortages: Vec<(Commodity, u32)> = history
            .shortage_ticks
            .iter()
            .filter(|(_, t)| **t > 0)
            .map(|(c, t)| (*c, *t))
            .collect();
        shortages.sort_by(|a, b| b.1.cmp(&a.1));

        let crisis = shortages
            .iter()
            .any(|(_, t)| *t >= MARKET_CRISIS_SHORTAGE_TICKS);
        let any_short = !shortages.is_empty();

        rows.push(MarketRow {
            location,
            prices,
            supply,
            demand,
            shortage_ticks: shortages,
            crisis,
            any_short,
        });
    }
    rows.sort_by(|a, b| {
        // Crises first, then shortages, then plain — each group
        // alphabetised. Makes the problem-spots jump to the top.
        let tier = |r: &MarketRow| -> u8 {
            if r.crisis {
                0
            } else if r.any_short {
                1
            } else {
                2
            }
        };
        tier(a).cmp(&tier(b)).then(a.location.cmp(&b.location))
    });

    let filter_lc = filter.to_lowercase();
    let filtered: Vec<&MarketRow> = rows
        .iter()
        .filter(|r| filter_lc.is_empty() || r.location.to_lowercase().contains(&filter_lc))
        .filter(|r| !only_shortages || r.any_short)
        .collect();

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Markets · {shown}/{total}"))
        .id(egui::Id::new("markets_window"))
        .default_width(760.0)
        .default_height(520.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
                ui.separator();
                ui.checkbox(&mut only_shortages, "only shortages");
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                for row in &filtered {
                    // Build the collapsing-header label inline so the
                    // tag (CRISIS / SHORT) sits next to the location
                    // name instead of below the section. The header
                    // accepts WidgetText, which won't take a styled
                    // RichText with background color out of the box —
                    // so we render the header via .show_unindented
                    // wrapped in a horizontal that paints location +
                    // chip side by side.
                    let header_text = match (row.crisis, row.any_short) {
                        (true, _) => Some((" CRISIS ", theme::DANGER)),
                        (false, true) => Some((" SHORT ", theme::WARN)),
                        _ => None,
                    };

                    let collapsing = egui::CollapsingHeader::new({
                        let mut t = egui::RichText::new(&row.location).strong();
                        if row.crisis {
                            t = t.color(theme::DANGER);
                        } else if row.any_short {
                            t = t.color(theme::WARN);
                        }
                        t
                    })
                    .id_salt(format!("market_hdr_{}", row.location));
                    let resp = collapsing.show(ui, |ui| {
                        if !row.shortage_ticks.is_empty() {
                            ui.label(
                                egui::RichText::new("Active shortages")
                                    .strong()
                                    .color(theme::WARN),
                            );
                            egui::Grid::new(format!("shortage_grid_{}", row.location))
                                .num_columns(2)
                                .spacing([10.0, 2.0])
                                .show(ui, |ui| {
                                    for (c, t) in &row.shortage_ticks {
                                        ui.label(c.as_str());
                                        let color = if *t >= MARKET_CRISIS_SHORTAGE_TICKS {
                                            theme::DANGER
                                        } else {
                                            theme::WARN
                                        };
                                        ui.colored_label(
                                            color,
                                            egui::RichText::new(format!("{t} ticks")).monospace(),
                                        );
                                        ui.end_row();
                                    }
                                });
                            ui.separator();
                        }

                        egui::Grid::new(format!("commodity_grid_{}", row.location))
                            .striped(true)
                            .num_columns(4)
                            .spacing([12.0, 2.0])
                            .show(ui, |ui| {
                                for header in ["Commodity", "Price", "Supply", "Demand"] {
                                    ui.label(
                                        egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                    );
                                }
                                ui.end_row();

                                // Union of commodities from the three maps — a
                                // commodity may appear in demand but not supply
                                // (or vice versa).
                                let mut commodities: Vec<Commodity> = row
                                    .prices
                                    .iter()
                                    .map(|(c, _)| *c)
                                    .chain(row.supply.iter().map(|(c, _)| *c))
                                    .chain(row.demand.iter().map(|(c, _)| *c))
                                    .collect();
                                commodities.sort_by_key(|c| c.as_str());
                                commodities.dedup();

                                for c in commodities {
                                    let price = row
                                        .prices
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(c.base_price());
                                    let sup = row
                                        .supply
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(0.0);
                                    let dem = row
                                        .demand
                                        .iter()
                                        .find(|(k, _)| *k == c)
                                        .map(|(_, v)| *v)
                                        .unwrap_or(0.0);

                                    ui.label(c.as_str());
                                    // Price banding vs the commodity's own
                                    // base — DANGER above 1.25× (scarcity),
                                    // SUCCESS below 0.75× (glut), TEXT in
                                    // the middle band. Glance reads >
                                    // precise number.
                                    let base = c.base_price();
                                    let price_color = if base > 0.0 {
                                        let r = price / base;
                                        if r >= 1.25 {
                                            theme::DANGER
                                        } else if r <= 0.75 {
                                            theme::SUCCESS
                                        } else {
                                            theme::TEXT
                                        }
                                    } else {
                                        theme::TEXT
                                    };
                                    ui.colored_label(
                                        price_color,
                                        egui::RichText::new(format!("{price:.1}")).monospace(),
                                    );
                                    ui.label(
                                        egui::RichText::new(format!("{sup:.0}"))
                                            .monospace()
                                            .color(theme::TEXT_DIM),
                                    );
                                    ui.label(
                                        egui::RichText::new(format!("{dem:.0}"))
                                            .monospace()
                                            .color(theme::TEXT_DIM),
                                    );
                                    ui.end_row();
                                }
                            });
                    });

                    // CRISIS / SHORT chip beside the header row,
                    // visible whether expanded or collapsed.
                    if let Some((label, color)) = header_text {
                        let header_rect = resp.header_response.rect;
                        let chip_pos =
                            egui::pos2(header_rect.right() + 8.0, header_rect.center().y);
                        ui.painter().text(
                            chip_pos,
                            egui::Align2::LEFT_CENTER,
                            label.trim(),
                            egui::FontId::proportional(11.0),
                            color,
                        );
                    }
                }
            });
        });

    state.open = open;
    state.filter = filter;
    state.only_shortages = only_shortages;
}

// =============================================================================
// Populations panel
// =============================================================================
//
// One row per population (~27 today). Columns cover the levers: count,
// sentiment, food satisfaction, total wealth, migration pressure. Sort
// by any numeric column; filter by label/location/faction. Sentiment
// and food cells colour-code against their natural ranges so stressed
// pops jump out.

#[derive(Resource)]
struct PopulationsState {
    open: bool,
    sort: PopSort,
    descending: bool,
    filter: String,
}

impl Default for PopulationsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("pops") || s.contains("populations") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: PopSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum PopSort {
    #[default]
    Label,
    Location,
    Count,
    Sentiment,
    Food,
    Wealth,
    Migration,
}

struct PopRow {
    label: String,
    demographic: String,
    location: String,
    faction: String,
    count: i64,
    sentiment: i32,
    food: i32,
    wealth: i64,
    // Migration pressure is f32; keep as f32 for display, sort via bits
    // so NaN doesn't panic.
    migration: f32,
}

fn populations_panel(mut ctx: EguiContexts, sim: Res<Sim>, mut state: ResMut<PopulationsState>) {
    use sim_core::agents::population::{PopDemographics, PopEconomy, PopIdentity, PopSentiment};

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<PopRow> = sim
        .store
        .world
        .query::<(&PopIdentity, &PopDemographics, &PopEconomy, &PopSentiment)>()
        .iter()
        .map(|(_e, (id, demo, econ, sent))| PopRow {
            label: id.label.clone(),
            demographic: id.demographic.clone(),
            location: id.facility_location.clone(),
            faction: id.faction_id.clone(),
            count: demo.population_count,
            sentiment: sent.overall_sentiment,
            food: sent.food_satisfaction,
            wealth: econ.total_wealth,
            migration: demo.migration_pressure,
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&PopRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.label.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.demographic.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            PopSort::Label => a.label.cmp(&b.label),
            PopSort::Location => a.location.cmp(&b.location),
            PopSort::Count => a.count.cmp(&b.count),
            PopSort::Sentiment => a.sentiment.cmp(&b.sentiment),
            PopSort::Food => a.food.cmp(&b.food),
            PopSort::Wealth => a.wealth.cmp(&b.wealth),
            // Bits-based ordering for f32 — safe for non-NaN values which
            // migration_pressure is by construction (clamped >= 0.0).
            PopSort::Migration => a
                .migration
                .partial_cmp(&b.migration)
                .unwrap_or(std::cmp::Ordering::Equal),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Populations · {shown}/{total}"))
        .id(egui::Id::new("populations_window"))
        .default_width(820.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("pops_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        pop_sort_header(ui, "Label", &mut sort, &mut descending, PopSort::Label);
                        ui.label(egui::RichText::new("Demo").strong().color(theme::TEXT_DIM));
                        pop_sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            PopSort::Location,
                        );
                        pop_sort_header(ui, "Count", &mut sort, &mut descending, PopSort::Count);
                        pop_sort_header(ui, "Sent", &mut sort, &mut descending, PopSort::Sentiment);
                        pop_sort_header(ui, "Food", &mut sort, &mut descending, PopSort::Food);
                        pop_sort_header(ui, "Wealth", &mut sort, &mut descending, PopSort::Wealth);
                        pop_sort_header(ui, "Mig", &mut sort, &mut descending, PopSort::Migration);
                        ui.end_row();

                        for r in &filtered {
                            ui.label(&r.label);
                            ui.label(egui::RichText::new(&r.demographic).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.location).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(format_int(r.count)).monospace());
                            ui.colored_label(
                                sentiment_color(r.sentiment),
                                egui::RichText::new(format!("{}", r.sentiment)).monospace(),
                            );
                            ui.colored_label(
                                food_color(r.food),
                                egui::RichText::new(format!("{}", r.food)).monospace(),
                            );
                            ui.label(egui::RichText::new(format_credits(r.wealth)).monospace());
                            // Migration pressure: DANGER ≥ 1.0 (likely
                            // to migrate next tick), WARN ≥ 0.5
                            // (stress building), TEXT_DIM otherwise.
                            let mig_color = if r.migration >= 1.0 {
                                theme::DANGER
                            } else if r.migration >= 0.5 {
                                theme::WARN
                            } else {
                                theme::TEXT_DIM
                            };
                            ui.colored_label(
                                mig_color,
                                egui::RichText::new(format!("{:.2}", r.migration)).monospace(),
                            );
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
    state.filter = filter;
}

fn pop_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut PopSort,
    descending: &mut bool,
    target: PopSort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    // Mirror the other panels: PRIMARY tint when active sort,
    // TEXT_DIM otherwise; frameless layout.
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Numeric-y columns default to descending (biggest first),
            // text-y columns default to ascending.
            *descending = !matches!(target, PopSort::Label | PopSort::Location);
        }
    }
}

fn sentiment_color(s: i32) -> egui::Color32 {
    // Pop sentiment: SUCCESS ≥ 50 (content), WARN ≥ 30 (drift),
    // mid-band amber-ish below zero, DANGER strictly negative
    // (migration / unrest territory). Two amber tiers so the curve
    // is gentler than the binary status_color helper would give.
    if s >= 50 {
        theme::SUCCESS
    } else if s >= 30 {
        theme::WARN
    } else if s >= 0 {
        // Halfway between WARN and DANGER for the "low but not yet
        // crisis" band. Stays in the warm range rather than jumping
        // straight to red.
        egui::Color32::from_rgb(230, 150, 100)
    } else {
        theme::DANGER
    }
}

fn food_color(f: i32) -> egui::Color32 {
    // Food sat scale is roughly 0..=100. <30 is "emergency water"
    // territory; >70 is comfortable. Same SUCCESS / WARN / DANGER
    // banding as the rest of the panels.
    theme::status_color(f as f32, (70.0, 30.0))
}

fn format_int(n: i64) -> String {
    // Thousands separator for population counts so "1204000" reads
    // as "1,204,000" at a glance.
    let s = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    let result: String = out.chars().rev().collect();
    if n < 0 {
        format!("-{}", result)
    } else {
        result
    }
}

// =============================================================================
// Ship details panel
// =============================================================================
//
// The "inspector as live debugger" payoff of the embedded arch. Reads
// every ship component directly from hecs — no snapshot marshalling —
// and renders one section per component. Opens when a ship is selected
// in the ship list; closes itself when the user clears the selection.

fn ship_details_panel(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
    mut selected: ResMut<SelectedShip>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::ship::{
        ShipAI, ShipCargo, ShipCrew, ShipCrewSkills, ShipEconomy, ShipFitting, ShipFuel,
        ShipIdentity, ShipLifecycle, ShipPosition, ShipProgression, ShipTransit,
    };

    let Some(ship_id) = selected.0.clone() else {
        return;
    };

    let Some(&entity) = sim.store.ship_by_id.get(&ship_id) else {
        // Ship was deleted / retired — clear selection so the panel
        // doesn't keep trying to render a ghost.
        selected.0 = None;
        return;
    };

    let mut still_open = true;
    // Captured by the egui closure; consulted after the closure ends
    // so we don't try to mutably borrow sim while a read-query is
    // still alive inside.
    let mut grant_xp_requested = false;
    let mut delete_requested = false;
    let mut heal_requested = false;
    // Refit request: (slot, slug) pair captured from the Fitting
    // dropdowns. None=keep current, Some((slot, slug)) = swap.
    let mut refit_request: Option<(sim_core::modules::Slot, &'static str)> = None;
    let title = format!("Ship · {}", ship_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut(), |ui| {
            let Ok(mut q) = sim.store.world.query_one::<(
                &ShipIdentity,
                &ShipPosition,
                &ShipTransit,
                &ShipCargo,
                &ShipFuel,
                &ShipEconomy,
                &ShipAI,
                &ShipCrew,
                &ShipCrewSkills,
                &ShipProgression,
                &ShipFitting,
                &ShipLifecycle,
            )>(entity) else {
                ui.label("(ship entity missing components)");
                return;
            };
            let Some((id, pos, transit, cargo, fuel, econ, ai, crew, skills, prog, fit, life)) =
                q.get()
            else {
                ui.label("(ship entity missing components)");
                return;
            };

            // Toolbar: camera focus + admin actions. Camera focus
            // writes a separate Resource so it's safe inline. Grant
            // XP / Delete flip local bools that the system processes
            // after the query borrow ends — hecs forbids concurrent
            // read and write on the same world.
            ui.horizontal(|ui| {
                if ui.button("Focus camera").clicked() {
                    let (x, y) = pos.position;
                    focus_req.0 = Some(Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR));
                }
                ui.separator();
                ui.label(egui::RichText::new("admin:").small().color(theme::TEXT_DIM));
                if ui
                    .button(egui::RichText::new("+100 XP").small())
                    .on_hover_text(
                        "Instantly grant 100 XP to this ship (embedded-client \
                         admin: mutates the hecs component in place, no HTTP).",
                    )
                    .clicked()
                {
                    grant_xp_requested = true;
                }
                if ui
                    .button(egui::RichText::new("Heal").small().color(theme::SUCCESS))
                    .on_hover_text(
                        "Refill fuel to capacity, reset crew morale+health to \
                         100, clear hunger + fatigue, and floor credits at 10k \
                         so the ship can afford docks. Unsticks broke / \
                         spiralling ships for debugging.",
                    )
                    .clicked()
                {
                    heal_requested = true;
                }
                if ui
                    .button(egui::RichText::new("Delete").small().color(theme::DANGER))
                    .on_hover_text(
                        "Destroy this ship. Releases any accepted contracts \
                         back to the board; PickedUp cargo is lost. In-memory \
                         only — a restart reloads the ship from DB.",
                    )
                    .clicked()
                {
                    delete_requested = true;
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                // Identity
                ui.label(theme::section_header("Identity"));
                egui::Grid::new("details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name");
                        ui.label(&id.name);
                        ui.end_row();
                        ui.label("Class");
                        ui.label(&id.class);
                        ui.end_row();
                        ui.label("Size");
                        ui.label(format!("{:?}", id.size));
                        ui.end_row();
                        ui.label("Faction");
                        ui.label(&id.faction_id);
                        ui.end_row();
                    });
                ui.separator();

                // Position / transit
                ui.label(theme::section_header("Position"));
                egui::Grid::new("details_pos")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("System");
                        ui.label(&pos.system_id);
                        ui.end_row();
                        ui.label("Location");
                        ui.label(pos.location_name.as_deref().unwrap_or("(in transit)"));
                        ui.end_row();
                        ui.label("Docked");
                        ui.label(if pos.docked_at.is_some() { "yes" } else { "no" });
                        ui.end_row();
                        ui.label("XY");
                        ui.label(format!("{:.1}, {:.1}", pos.position.0, pos.position.1));
                        ui.end_row();
                        if let Some(t) = &transit.transit {
                            let progress = if t.distance_total > 0.0 {
                                (t.distance_travelled / t.distance_total).clamp(0.0, 1.0) * 100.0
                            } else {
                                0.0
                            };
                            ui.label("Transit");
                            ui.label(format!("{} → {} ({:.1}%)", t.from, t.to, progress,));
                            ui.end_row();
                            ui.label("Arrival tick");
                            ui.label(format!("{}", t.arrival_tick));
                            ui.end_row();
                        }
                    });
                ui.separator();

                // Economy
                ui.label(theme::section_header("Economy"));
                egui::Grid::new("details_econ")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits");
                        ui.label(format_credits(econ.credits));
                        ui.end_row();
                        ui.label("Efficiency");
                        ui.label(format!("{:.2}", econ.efficiency));
                        ui.end_row();
                        ui.label("Active contract");
                        ui.label(econ.active_contract_id.as_deref().unwrap_or("—"));
                        ui.end_row();
                    });
                if !econ.faction_reputation.is_empty() {
                    ui.label(egui::RichText::new("Reputation").italics().small());
                    egui::Grid::new("details_rep")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            let mut reps: Vec<_> = econ.faction_reputation.iter().collect();
                            reps.sort_by(|a, b| b.1.cmp(a.1));
                            for (faction, rep) in reps {
                                ui.label(faction);
                                ui.label(format!("{}", rep));
                                ui.end_row();
                            }
                        });
                }
                ui.separator();

                // Fuel
                ui.label(theme::section_header("Fuel"));
                egui::Grid::new("details_fuel")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        let frac = fuel.fraction();
                        let frac_color = theme::status_color(frac, (0.5, 0.2));
                        ui.label(theme::caption("Fuel"));
                        ui.colored_label(
                            frac_color,
                            egui::RichText::new(format!(
                                "{:.1} / {:.0} ({:.0}%)",
                                fuel.fuel,
                                fuel.fuel_capacity,
                                frac * 100.0
                            ))
                            .monospace(),
                        );
                        ui.end_row();
                        ui.label(theme::caption("Speed mod"));
                        ui.label(
                            egui::RichText::new(format!("{:.2}×", fuel.speed_modifier)).monospace(),
                        );
                        ui.end_row();
                        ui.label(theme::caption("Burn rate"));
                        ui.label(
                            egui::RichText::new(format!("{:.3}", fuel.fuel_consumption_rate))
                                .monospace(),
                        );
                        ui.end_row();
                    });
                ui.separator();

                // Cargo
                ui.label(theme::section_header("Cargo"));
                let used = cargo.used();
                ui.label(format!(
                    "Hold: {} / {} ({:.0}%)",
                    used,
                    cargo.capacity,
                    if cargo.capacity > 0 {
                        used as f32 / cargo.capacity as f32 * 100.0
                    } else {
                        0.0
                    }
                ));
                if !cargo.cargo.is_empty() {
                    egui::Grid::new("details_cargo")
                        .num_columns(2)
                        .spacing([10.0, 2.0])
                        .show(ui, |ui| {
                            let mut items: Vec<_> = cargo.cargo.iter().collect();
                            items.sort_by_key(|(c, _)| c.as_str());
                            for (c, qty) in items {
                                ui.label(c.as_str());
                                ui.label(format!("{}", qty));
                                ui.end_row();
                            }
                        });
                }
                ui.separator();

                // Crew
                ui.label(theme::section_header("Crew"));
                egui::Grid::new("details_crew")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Size");
                        ui.label(format!("{}", crew.size));
                        ui.end_row();
                        ui.label("Task");
                        ui.label(crew.current_task.as_str());
                        ui.end_row();
                        ui.label("Morale");
                        ui.colored_label(
                            theme::crew_bar_color(crew.morale),
                            format!("{:.0}", crew.morale),
                        );
                        ui.end_row();
                        ui.label("Hunger");
                        ui.colored_label(
                            // Inverse scale — hunger high = bad.
                            theme::crew_bar_color(100.0 - crew.hunger),
                            format!("{:.0}", crew.hunger),
                        );
                        ui.end_row();
                        ui.label("Fatigue");
                        ui.colored_label(
                            theme::crew_bar_color(100.0 - crew.fatigue),
                            format!("{:.0}", crew.fatigue),
                        );
                        ui.end_row();
                        ui.label("Health");
                        ui.label(format!("{:.0}", crew.health));
                        ui.end_row();
                        ui.label("Wages owed");
                        ui.label(format!("{}", crew.wages_credits));
                        ui.end_row();
                        ui.label("Skills");
                        ui.label(format!(
                            "nav {}  eng {}  trd {}  cmb {}",
                            skills.navigation, skills.engineering, skills.trading, skills.combat,
                        ));
                        ui.end_row();
                    });
                ui.separator();

                // AI
                ui.label(theme::section_header("AI"));
                egui::Grid::new("details_ai")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Goal");
                        ui.label(&ai.current_goal);
                        ui.end_row();
                        ui.label("Goal score");
                        ui.label(format!("{:.2}", ai.current_goal_score));
                        ui.end_row();
                        ui.label("Planned at tick");
                        ui.label(format!("{}", ai.last_plan_tick));
                        ui.end_row();
                        ui.label("Personality");
                        ui.label(format!(
                            "profit {:.2}  safety {:.2}  morale {:.2}  explore {:.2}",
                            ai.personality.profit,
                            ai.personality.safety,
                            ai.personality.morale,
                            ai.personality.exploration,
                        ));
                        ui.end_row();
                    });
                ui.separator();

                // Progression
                ui.label(theme::section_header("Progression"));
                egui::Grid::new("details_prog")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!(
                            "{} / {}",
                            prog.level,
                            sim_core::agents::ship::SHIP_LEVEL_CAP
                        ));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", prog.xp, prog.next_level_threshold()));
                        ui.end_row();
                        ui.label("Retrofit points");
                        ui.label(format!("{}", prog.retrofit_points));
                        ui.end_row();
                        ui.label("Idle ticks");
                        ui.label(format!("{}", life.idle_ticks));
                        ui.end_row();
                        ui.label("Broke / hoard strikes");
                        ui.label(format!("{} / {}", life.broke_strikes, life.hoard_strikes));
                        ui.end_row();
                    });
                ui.separator();

                // Fitting — interactive: each slot row is a combo
                // of compatible module slugs. Selecting a different
                // slug fires an admin-override refit (no cost / no
                // shipyard stock check) via sim_server::engine::
                // admin_refit_ship after the read-query drops. Empty
                // slot still shows "—" but we don't expose unset as
                // a choice to reduce footguns.
                ui.label(theme::section_header("Fitting"));
                egui::Grid::new("details_fit")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        for (slot_idx, slot) in sim_core::modules::SLOTS.iter().enumerate() {
                            ui.label(slot.as_str());
                            let current = fit.slots[slot_idx];
                            let current_label = current.unwrap_or("—");
                            egui::ComboBox::from_id_salt(format!("refit_combo_{}", slot.as_str()))
                                .selected_text(current_label)
                                .show_ui(ui, |ui| {
                                    for module in sim_core::modules::modules_for_slot(*slot) {
                                        let label = format!("{} (T{})", module.slug, module.tier);
                                        if ui
                                            .selectable_label(current == Some(module.slug), label)
                                            .clicked()
                                            && current != Some(module.slug)
                                        {
                                            refit_request = Some((*slot, module.slug));
                                        }
                                    }
                                });
                            ui.end_row();
                        }
                        ui.label("Sensor range");
                        ui.label(format!("{:.1} AU", fit.derived.sensor_range_au));
                        ui.end_row();
                        ui.label("Cargo mult");
                        ui.label(format!("{:.2}×", fit.derived.cargo_capacity_mult));
                        ui.end_row();
                        ui.label("Speed mult");
                        ui.label(format!("{:.2}×", fit.derived.speed_mult));
                        ui.end_row();
                        ui.label("Comms bonus");
                        ui.label(format!("{:+.2}", fit.derived.comms_bonus));
                        ui.end_row();
                    });
            });
        });

    if grant_xp_requested {
        use sim_core::agents::ship::ShipProgression;
        if let Ok(mut prog) = sim.store.world.get::<&mut ShipProgression>(entity) {
            let levels = prog.grant_xp(100);
            info!(
                "client_bevy admin: +100 XP to {} ({}level+{})",
                ship_id,
                if levels > 0 { "leveled up! " } else { "" },
                prog.retrofit_points,
            );
        }
    }

    if let Some((slot, slug)) = refit_request {
        // via_shipyard=false → admin override path: no cost, no
        // shipyard stock decrement. Matches the HTTP admin/refit
        // endpoint behaviour for the no-cost form.
        let mut refit_events: Vec<serde_json::Value> = Vec::new();
        sim_server::engine::admin_refit_ship(
            &mut sim.store,
            &ship_id,
            slot,
            Some(slug),
            false,
            &mut refit_events,
        );
        info!(
            "client_bevy admin: refit {} {} → {}",
            ship_id,
            slot.as_str(),
            slug,
        );
    }

    if heal_requested {
        use sim_core::agents::ship::{ShipCrew, ShipEconomy, ShipFuel};
        // Drop borrows one at a time — hecs only allows one mutable
        // query per component per scope. Each `get::<&mut _>` scopes
        // to the `if let` block.
        if let Ok(mut fuel) = sim.store.world.get::<&mut ShipFuel>(entity) {
            fuel.fuel = fuel.fuel_capacity;
        }
        if let Ok(mut crew) = sim.store.world.get::<&mut ShipCrew>(entity) {
            crew.morale = 100.0;
            crew.health = 100.0;
            crew.hunger = 0.0;
            crew.fatigue = 0.0;
        }
        if let Ok(mut econ) = sim.store.world.get::<&mut ShipEconomy>(entity) {
            // Floor — don't zap a millionaire ship back to 10k. Just
            // make sure a stranded ship has dock money.
            if econ.credits < 10_000 {
                econ.credits = 10_000;
            }
        }
        info!("client_bevy admin: healed {}", ship_id);
    }

    if delete_requested {
        use sim_core::agents::facility::FacilityStorage;
        // Step 1: yank the ship entity out of any docked list + dock
        // queue. If we skip this the entry wedges behind a despawned
        // entity and blocks live ships behind it. Mirrors the admin
        // cascade in sim_server::engine::admin_remove_ship.
        for (_e, storage) in sim.store.world.query_mut::<&mut FacilityStorage>() {
            storage.docked_ships.retain(|&e| e != entity);
            storage.dock_queue.retain(|&e| e != entity);
        }
        // Step 2: release any contracts tied to this ship. Accepted
        // → Posted (re-postable); PickedUp → Expired (cargo lost with
        // the ship). `drop` is ignored here because the client
        // doesn't broadcast events the way sim_server does.
        let _ = sim.store.contracts.drop_ship_holdings(&ship_id);
        // Step 3: actually despawn + forget the id mapping.
        let _ = sim.store.world.despawn(entity);
        sim.store.ship_by_id.remove(&ship_id);
        info!("client_bevy admin: deleted ship {}", ship_id);
        // Clear selection so the details panel closes cleanly on the
        // next frame (entity lookup will fail either way, but being
        // explicit avoids one wasted frame of "entity missing"
        // render).
        selected.0 = None;
        // Render entities in Bevy still reference the dead sim entity
        // via ShipEntity.sim_id; sync_positions leaves them in place
        // because there's no matching id in ship_state. That means
        // the Bevy ship mesh lingers until restart, which is OK for
        // embedded admin-mode but worth noting — a cleanup system
        // that despawns stale Bevy entities when sim_id isn't found
        // would land cleanly here if it ever becomes distracting.
        return;
    }

    if !still_open {
        selected.0 = None;
    }
}

// =============================================================================
// Facility list + details
// =============================================================================
//
// Mirrors ships: a filterable/sortable list; clicking a row sets
// SelectedFacility, opening a details panel with everything on the
// facility entity. Both list and details read hecs directly.

#[derive(Resource)]
struct FacilityListState {
    open: bool,
    sort: FacilitySort,
    descending: bool,
    filter: String,
}

impl Default for FacilityListState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("facilities") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: FacilitySort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum FacilitySort {
    #[default]
    Name,
    Type,
    Faction,
    Location,
    Credits,
    Docked,
    Level,
}

#[derive(Resource, Default)]
pub struct SelectedFacility(pub Option<String>);

struct FacilityRow {
    id: String,
    name: String,
    facility_type: String,
    faction: String,
    location: String,
    credits: i64,
    docked: u32,
    capacity: u32,
    level: u8,
    abandoned: bool,
}

fn facility_list_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<FacilityListState>,
    mut selected: ResMut<SelectedFacility>,
) {
    use sim_core::agents::facility::{
        FacilityIdentity, FacilityLifecycle, FacilityLocation, FacilityOperations, FacilityStorage,
    };

    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let rows: Vec<FacilityRow> = sim
        .store
        .world
        .query::<(
            &FacilityIdentity,
            &FacilityLocation,
            &FacilityOperations,
            &FacilityStorage,
            &FacilityLifecycle,
        )>()
        .iter()
        .map(|(_e, (id, loc, ops, stor, life))| FacilityRow {
            id: id.id.clone(),
            name: id.name.clone(),
            facility_type: id.facility_type.clone(),
            faction: id.faction_id.clone(),
            location: loc.location_name.clone(),
            credits: ops.credits,
            docked: stor.docked_ships.len() as u32,
            capacity: ops.docking_capacity,
            level: life.level,
            abandoned: life.abandoned,
        })
        .collect();

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&FacilityRow> = rows
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.id.to_lowercase().contains(&filter_lc)
                || r.facility_type.to_lowercase().contains(&filter_lc)
                || r.faction.to_lowercase().contains(&filter_lc)
                || r.location.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            FacilitySort::Name => a.name.cmp(&b.name),
            FacilitySort::Type => a.facility_type.cmp(&b.facility_type),
            FacilitySort::Faction => a.faction.cmp(&b.faction),
            FacilitySort::Location => a.location.cmp(&b.location),
            FacilitySort::Credits => a.credits.cmp(&b.credits),
            FacilitySort::Docked => a.docked.cmp(&b.docked),
            FacilitySort::Level => a.level.cmp(&b.level),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = rows.len();
    let shown = filtered.len();

    egui::Window::new(format!("Facilities · {shown}/{total}"))
        .id(egui::Id::new("facilities_window"))
        .default_width(800.0)
        .default_height(460.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("facility_list_grid")
                    .striped(true)
                    .num_columns(7)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        fac_sort_header(ui, "Name", &mut sort, &mut descending, FacilitySort::Name);
                        fac_sort_header(ui, "Type", &mut sort, &mut descending, FacilitySort::Type);
                        fac_sort_header(
                            ui,
                            "Faction",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Faction,
                        );
                        fac_sort_header(
                            ui,
                            "Location",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Location,
                        );
                        fac_sort_header(
                            ui,
                            "Credits",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Credits,
                        );
                        fac_sort_header(
                            ui,
                            "Dock",
                            &mut sort,
                            &mut descending,
                            FacilitySort::Docked,
                        );
                        fac_sort_header(ui, "Lvl", &mut sort, &mut descending, FacilitySort::Level);
                        ui.end_row();

                        for r in &filtered {
                            let is_sel = selected.0.as_deref() == Some(r.id.as_str());
                            let name_text = if r.abandoned {
                                egui::RichText::new(&r.name)
                                    .color(theme::TEXT_DIM)
                                    .strikethrough()
                            } else {
                                egui::RichText::new(&r.name)
                            };
                            if ui.selectable_label(is_sel, name_text).clicked() {
                                selected.0 = Some(r.id.clone());
                            }
                            ui.label(&r.facility_type);
                            ui.label(&r.faction);
                            ui.label(&r.location);
                            ui.label(format_credits(r.credits));
                            ui.label(format!("{}/{}", r.docked, r.capacity));
                            ui.label(format!("{}", r.level));
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.sort = sort;
    state.descending = descending;
    state.filter = filter;
}

fn fac_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut FacilitySort,
    descending: &mut bool,
    target: FacilitySort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            *descending = matches!(
                target,
                FacilitySort::Credits | FacilitySort::Docked | FacilitySort::Level,
            );
        }
    }
}

fn facility_details_panel(
    mut ctx: EguiContexts,
    sim: ResMut<Sim>,
    mut selected: ResMut<SelectedFacility>,
    mut focus_req: ResMut<CameraFocusRequest>,
    mut ship_sel: ResMut<SelectedShip>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{
        FacilityCrew, FacilityFitting, FacilityIdentity, FacilityLifecycle, FacilityLocation,
        FacilityOperations, FacilityStorage,
    };

    let Some(fac_id) = selected.0.clone() else {
        return;
    };
    let Some(&entity) = sim.store.facility_by_id.get(&fac_id) else {
        selected.0 = None;
        return;
    };

    let mut still_open = true;
    // Captured by the egui closure; consulted after the closure
    // ends so admin mutations don't conflict with the read-only
    // query that's live inside.
    let mut refill_requested = false;
    // Per-commodity reserve deltas captured by the +/- buttons in
    // the Reserves grid. Applied after the read-only query drops.
    let mut reserves_deltas: Vec<(sim_core::economy::commodities::Commodity, f32)> = Vec::new();
    // Optional "add new commodity" pick; if Some, the apply pass
    // inserts an entry initialised to 100 units.
    let mut add_commodity: Option<sim_core::economy::commodities::Commodity> = None;
    let title = format!("Facility · {}", fac_id);

    egui::Window::new(title)
        .default_width(520.0)
        .default_height(640.0)
        .open(&mut still_open)
        .show(ctx.ctx_mut(), |ui| {
            let Ok(mut q) = sim.store.world.query_one::<(
                &FacilityIdentity,
                &FacilityLocation,
                &FacilityOperations,
                &FacilityStorage,
                &FacilityLifecycle,
            )>(entity) else {
                ui.label("(facility entity missing components)");
                return;
            };
            let Some((id, loc, ops, storage, life)) = q.get() else {
                ui.label("(facility entity missing components)");
                return;
            };

            // Optional components — gates don't have fitting/crew, so
            // wrap each in a separate query that degrades gracefully.
            let fitting = sim
                .store
                .world
                .query_one::<&FacilityFitting>(entity)
                .ok()
                .and_then(|mut q| q.get().cloned());
            let crew = sim
                .store
                .world
                .query_one::<&FacilityCrew>(entity)
                .ok()
                .and_then(|mut q| q.get().cloned());

            // Toolbar: focus camera + admin actions. Focus writes a
            // separate Resource (safe inline); Refill flips the
            // outer bool we apply after the read-query drops.
            ui.horizontal(|ui| {
                if ui.button("Focus camera").clicked() {
                    let body_pos = sim
                        .store
                        .world
                        .query::<(&BodyIdentity, &BodyOrbit)>()
                        .iter()
                        .find(|(_e, (b, _))| b.body_id == id.body_id)
                        .map(|(_e, (_, o))| o.universe_position());
                    if let Some((x, y)) = body_pos {
                        focus_req.0 = Some(Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR));
                    }
                }
                ui.separator();
                ui.label(egui::RichText::new("admin:").small().color(theme::TEXT_DIM));
                if ui
                    .button(egui::RichText::new("Refill reserves").small())
                    .on_hover_text(
                        "Floor every commodity entry in this facility's \
                         reserves at 500 units. Use to unstick starving \
                         facilities during testing without rebuilding the \
                         whole market.",
                    )
                    .clicked()
                {
                    refill_requested = true;
                }
            });
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                if life.abandoned {
                    ui.colored_label(theme::DANGER, egui::RichText::new("ABANDONED").strong());
                    ui.separator();
                }

                ui.label(theme::section_header("Identity"));
                egui::Grid::new("fac_details_identity")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Name");
                        ui.label(&id.name);
                        ui.end_row();
                        ui.label("Type");
                        ui.label(&id.facility_type);
                        ui.end_row();
                        ui.label("Body");
                        ui.label(&id.body_id);
                        ui.end_row();
                        ui.label("Location");
                        ui.label(&loc.location_name);
                        ui.end_row();
                        ui.label("Faction");
                        ui.label(&id.faction_id);
                        ui.end_row();
                    });
                ui.separator();

                ui.label(theme::section_header("Operations"));
                egui::Grid::new("fac_details_ops")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Credits");
                        ui.label(format_credits(ops.credits));
                        ui.end_row();
                        ui.label("Condition");
                        let cond_color = theme::status_color(ops.condition, (0.7, 0.3));
                        ui.colored_label(cond_color, format!("{:.0}%", ops.condition * 100.0));
                        ui.end_row();
                        ui.label("Docking");
                        ui.label(format!(
                            "{} / {} (+{} queued)",
                            storage.docked_ships.len(),
                            ops.docking_capacity,
                            storage.dock_queue.len(),
                        ));
                        ui.end_row();
                    });
                ui.separator();

                ui.label(theme::section_header("Lifecycle"));
                egui::Grid::new("fac_details_life")
                    .num_columns(2)
                    .spacing([12.0, 2.0])
                    .show(ui, |ui| {
                        ui.label("Level");
                        ui.label(format!(
                            "{} / {}",
                            life.level,
                            sim_core::agents::facility::FACILITY_LEVEL_CAP
                        ));
                        ui.end_row();
                        ui.label("XP");
                        ui.label(format!("{} / {}", life.xp, life.next_level_threshold()));
                        ui.end_row();
                        if life.abandon_counter > 0 {
                            ui.label("Abandon countdown");
                            ui.label(format!("{}", life.abandon_counter));
                            ui.end_row();
                        }
                    });
                ui.separator();

                ui.label(theme::section_header("Reserves"));
                if storage.reserves.is_empty() {
                    ui.label(
                        egui::RichText::new("(no reserves)")
                            .italics()
                            .color(theme::TEXT_DIM),
                    );
                } else {
                    egui::Grid::new("fac_details_reserves")
                        .striped(true)
                        .num_columns(5)
                        .spacing([6.0, 2.0])
                        .show(ui, |ui| {
                            let mut items: Vec<_> = storage.reserves.iter().collect();
                            items.sort_by_key(|(c, _)| c.as_str());
                            for (c, qty) in items {
                                ui.label(c.as_str());
                                ui.label(egui::RichText::new(format!("{:.0}", qty)).monospace());
                                if ui
                                    .add(egui::Button::new("-100").small())
                                    .on_hover_text("Subtract 100 units (floored at 0).")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, -100.0));
                                }
                                if ui
                                    .add(egui::Button::new("+100").small())
                                    .on_hover_text("Add 100 units.")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, 100.0));
                                }
                                if ui
                                    .add(egui::Button::new("+1k").small())
                                    .on_hover_text("Add 1000 units — quick top-up.")
                                    .clicked()
                                {
                                    reserves_deltas.push((*c, 1000.0));
                                }
                                ui.end_row();
                            }
                        });
                }
                // "Add commodity" picker — list any commodity not
                // already in reserves so the user can introduce a new
                // line without typing a string. Initialises new
                // entries at 100 units (small enough to feel like a
                // delta, big enough to be visible).
                ui.horizontal(|ui| {
                    let existing: std::collections::HashSet<_> =
                        storage.reserves.keys().copied().collect();
                    let missing: Vec<_> = sim_core::economy::commodities::Commodity::ALL
                        .iter()
                        .copied()
                        .filter(|c| !existing.contains(c))
                        .collect();
                    if !missing.is_empty() {
                        ui.label(theme::caption("Add"));
                        egui::ComboBox::from_id_salt("fac_reserves_add")
                            .selected_text("(pick a commodity)")
                            .show_ui(ui, |ui| {
                                for c in &missing {
                                    if ui.selectable_label(false, c.as_str()).clicked() {
                                        add_commodity = Some(*c);
                                    }
                                }
                            });
                    }
                });
                ui.separator();

                if let Some(fit) = fitting {
                    ui.label(theme::section_header("Fitting"));
                    egui::Grid::new("fac_details_fit")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            for slot in sim_core::facility_modules::FACILITY_SLOTS.iter() {
                                ui.label(slot.as_str());
                                ui.label(fit.slots[slot.index()].unwrap_or("—"));
                                ui.end_row();
                            }
                            ui.label("Recipe output mult");
                            ui.label(format!("{:.2}×", fit.derived.recipe_output_mult));
                            ui.end_row();
                            ui.label("Max batches bonus");
                            ui.label(format!("+{}", fit.derived.max_batches_bonus));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if let Some(crew) = crew {
                    ui.label(theme::section_header("Crew"));
                    egui::Grid::new("fac_details_crew")
                        .num_columns(2)
                        .spacing([12.0, 2.0])
                        .show(ui, |ui| {
                            ui.label("Count");
                            ui.label(format!("{}", crew.crew_count));
                            ui.end_row();
                            ui.label("Morale");
                            ui.colored_label(
                                theme::crew_bar_color(crew.morale),
                                format!("{:.0}", crew.morale),
                            );
                            ui.end_row();
                            ui.label("Hunger");
                            ui.colored_label(
                                theme::crew_bar_color(100.0 - crew.hunger),
                                format!("{:.0}", crew.hunger),
                            );
                            ui.end_row();
                            ui.label("Efficiency");
                            ui.label(format!("{:.2}×", crew.efficiency()));
                            ui.end_row();
                        });
                    ui.separator();
                }

                if !storage.docked_ships.is_empty() || !storage.dock_queue.is_empty() {
                    ui.label(theme::section_header("Dock"));
                    // Resolve each docked / queued entity back to
                    // its ShipIdentity so the panel can name them.
                    // Cheap even at Haven's 45-capacity — 45 hecs
                    // query_ones per facility click, maybe once a
                    // second when the user is browsing.
                    use sim_core::agents::ship::ShipIdentity;
                    // Resolve a docked / queued entity back to
                    // (id, label). id is the sim_id we use for
                    // selection; label is "<name> (<class>)".
                    let resolve = |e| {
                        sim.store
                            .world
                            .query_one::<&ShipIdentity>(e)
                            .ok()
                            .and_then(|mut q| {
                                q.get().map(|id| {
                                    (id.id.clone(), format!("{} ({})", id.name, id.class))
                                })
                            })
                    };

                    if !storage.docked_ships.is_empty() {
                        ui.label(
                            egui::RichText::new(format!("Docked ({})", storage.docked_ships.len()))
                                .italics()
                                .color(theme::TEXT_DIM),
                        );
                        for &e in &storage.docked_ships {
                            if let Some((sim_id, label)) = resolve(e) {
                                if ui
                                    .selectable_label(false, egui::RichText::new(label).small())
                                    .on_hover_text("Select this docked ship")
                                    .clicked()
                                {
                                    ship_sel.0 = Some(sim_id);
                                }
                            }
                        }
                    }
                    if !storage.dock_queue.is_empty() {
                        ui.label(
                            egui::RichText::new(format!(
                                "Queue ({} waiting)",
                                storage.dock_queue.len()
                            ))
                            .italics()
                            .color(theme::WARN),
                        );
                        for (i, &e) in storage.dock_queue.iter().enumerate() {
                            if let Some((sim_id, label)) = resolve(e) {
                                let line = format!("{:>2}. {}", i + 1, label);
                                if ui
                                    .selectable_label(false, egui::RichText::new(line).small())
                                    .on_hover_text("Select this queued ship")
                                    .clicked()
                                {
                                    ship_sel.0 = Some(sim_id);
                                }
                            }
                        }
                    }
                    if !storage.pending_deliveries.is_empty() {
                        ui.label(format!(
                            "Pending deliveries: {}",
                            storage.pending_deliveries.len()
                        ));
                    }
                }
            });
        });

    if refill_requested {
        use sim_core::agents::facility::FacilityStorage;
        use sim_core::economy::commodities::Commodity;
        if let Ok(mut storage) = sim.store.world.get::<&mut FacilityStorage>(entity) {
            // Floor each commodity's reserve at 500. Don't downgrade
            // a richer facility — admins use this to recover from
            // crisis, not to nuke a healthy stockpile.
            for c in Commodity::ALL.iter().copied() {
                let entry = storage.reserves.entry(c).or_insert(0.0);
                if *entry < 500.0 {
                    *entry = 500.0;
                }
            }
            info!("client_bevy admin: refilled reserves on {fac_id}");
        }
    }

    // Apply per-commodity reserve deltas + new-commodity inserts
    // captured by the buttons inside the read-only render closure.
    if !reserves_deltas.is_empty() || add_commodity.is_some() {
        use sim_core::agents::facility::FacilityStorage;
        if let Ok(mut storage) = sim.store.world.get::<&mut FacilityStorage>(entity) {
            for (c, d) in reserves_deltas {
                let entry = storage.reserves.entry(c).or_insert(0.0);
                *entry = (*entry + d).max(0.0);
            }
            if let Some(c) = add_commodity {
                storage.reserves.entry(c).or_insert(100.0);
            }
        }
    }

    if !still_open {
        selected.0 = None;
    }
}

// =============================================================================
// Retirements panel
// =============================================================================
//
// Historical ship losses, loaded once at startup from the `retired_ships`
// table. Post-mortem view: name, class, faction, final credits + fuel
// + morale, the strike counters that tipped them into auto-retirement,
// the reason string, and the tick they retired at. Filter + sort.

#[derive(Resource)]
struct RetirementsState {
    open: bool,
    sort: RetirementSort,
    descending: bool,
    filter: String,
}

impl Default for RetirementsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("retired") || s.contains("retirements") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            sort: RetirementSort::default(),
            descending: false,
            filter: String::new(),
        }
    }
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
enum RetirementSort {
    #[default]
    Tick,
    Name,
    Class,
    Faction,
    Credits,
    Reason,
}

fn retirements_panel(
    mut ctx: EguiContexts,
    retirements: Res<Retirements>,
    mut state: ResMut<RetirementsState>,
) {
    let mut open = state.open;
    let mut sort = state.sort;
    let mut descending = state.descending;
    let mut filter = state.filter.clone();

    if !open {
        return;
    }

    let filter_lc = filter.to_lowercase();
    let mut filtered: Vec<&sim_db::persistence::RetirementRow> = retirements
        .0
        .iter()
        .filter(|r| {
            if filter_lc.is_empty() {
                return true;
            }
            r.name.to_lowercase().contains(&filter_lc)
                || r.agent_id.to_lowercase().contains(&filter_lc)
                || r.class.to_lowercase().contains(&filter_lc)
                || r.faction_id.to_lowercase().contains(&filter_lc)
                || r.final_location.to_lowercase().contains(&filter_lc)
                || r.reason.to_lowercase().contains(&filter_lc)
        })
        .collect();

    filtered.sort_by(|a, b| {
        let cmp = match sort {
            RetirementSort::Tick => a.retired_at_tick.cmp(&b.retired_at_tick),
            RetirementSort::Name => a.name.cmp(&b.name),
            RetirementSort::Class => a.class.cmp(&b.class),
            RetirementSort::Faction => a.faction_id.cmp(&b.faction_id),
            RetirementSort::Credits => a.final_credits.cmp(&b.final_credits),
            RetirementSort::Reason => a.reason.cmp(&b.reason),
        };
        if descending {
            cmp.reverse()
        } else {
            cmp
        }
    });

    let total = retirements.0.len();
    let shown = filtered.len();

    egui::Window::new(format!("Retired · {shown}/{total}"))
        .id(egui::Id::new("retired_window"))
        .default_width(860.0)
        .default_height(480.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter:");
                ui.text_edit_singleline(&mut filter);
            });
            ui.label(
                egui::RichText::new(
                    "Snapshot of past decommissions. Newest-first by default. \
                     Loaded once at startup — new retirements during play \
                     will appear after a restart.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
            ui.separator();

            if total == 0 {
                ui.label(
                    egui::RichText::new("(no retirements yet — fresh DB or no decommissions)")
                        .italics()
                        .color(theme::TEXT_DIM),
                );
                return;
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                egui::Grid::new("retirements_grid")
                    .striped(true)
                    .num_columns(8)
                    .spacing([12.0, 3.0])
                    .show(ui, |ui| {
                        ret_sort_header(
                            ui,
                            "Tick",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Tick,
                        );
                        ret_sort_header(
                            ui,
                            "Name",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Name,
                        );
                        ret_sort_header(
                            ui,
                            "Class",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Class,
                        );
                        ret_sort_header(
                            ui,
                            "Faction",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Faction,
                        );
                        ui.label(
                            egui::RichText::new("Location")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ret_sort_header(
                            ui,
                            "Credits",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Credits,
                        );
                        ui.label(
                            egui::RichText::new("Morale / Fuel")
                                .strong()
                                .color(theme::TEXT_DIM),
                        );
                        ret_sort_header(
                            ui,
                            "Reason",
                            &mut sort,
                            &mut descending,
                            RetirementSort::Reason,
                        );
                        ui.end_row();

                        for r in &filtered {
                            ui.label(
                                egui::RichText::new(format!("{}", r.retired_at_tick)).monospace(),
                            );
                            ui.label(&r.name);
                            ui.label(egui::RichText::new(&r.class).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.faction_id).color(theme::TEXT_DIM));
                            ui.label(egui::RichText::new(&r.final_location).color(theme::TEXT_DIM));
                            ui.label(
                                egui::RichText::new(format_credits(r.final_credits)).monospace(),
                            );
                            ui.label(
                                egui::RichText::new(format!(
                                    "{} / {}",
                                    r.final_crew_morale, r.final_fuel_pct
                                ))
                                .monospace()
                                .color(theme::TEXT_DIM),
                            );
                            ui.colored_label(reason_color(&r.reason), &r.reason);
                            ui.end_row();
                        }
                    });
            });
        });

    state.open = open;
    state.filter = filter;
    state.sort = sort;
    state.descending = descending;
}

fn ret_sort_header(
    ui: &mut egui::Ui,
    label: &str,
    current: &mut RetirementSort,
    descending: &mut bool,
    target: RetirementSort,
) {
    let arrow = if *current == target {
        if *descending {
            " ▼"
        } else {
            " ▲"
        }
    } else {
        ""
    };
    let active = *current == target;
    let color = if active {
        theme::PRIMARY
    } else {
        theme::TEXT_DIM
    };
    let text = egui::RichText::new(format!("{label}{arrow}"))
        .strong()
        .color(color);
    if ui.add(egui::Button::new(text).frame(false)).clicked() {
        if *current == target {
            *descending = !*descending;
        } else {
            *current = target;
            // Tick + credits default descending (newest / richest
            // first); text columns ascending.
            *descending = matches!(target, RetirementSort::Tick | RetirementSort::Credits,);
        }
    }
}

fn reason_color(reason: &str) -> egui::Color32 {
    // Theme-mapped colouring against the known strike kinds.
    // Anything else (future causes) renders neutral TEXT.
    let lc = reason.to_lowercase();
    if lc.contains("broke") {
        theme::DANGER
    } else if lc.contains("hoard") {
        theme::WARN
    } else if lc.contains("admin") {
        theme::PRIMARY
    } else {
        theme::TEXT
    }
}

// =============================================================================
// Construction sites panel
// =============================================================================
//
// Phase 19c sites — one row per pending build, with a progress bar
// for delivered / required cargo. "Focus" button jumps the camera to
// the site's universe position (same coordinate space as the body/
// facility render). Lists the commodity each delivery consumes and
// the faction sponsoring the build.

#[derive(Resource)]
struct ConstructionState {
    open: bool,
}

impl Default for ConstructionState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("construction") || s == "all")
            .unwrap_or(false);
        Self { open: auto_open }
    }
}

fn construction_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<ConstructionState>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::construction::ConstructionSite;

    let mut open = state.open;
    if !open {
        return;
    }

    struct Row {
        id: String,
        name: String,
        facility_type: String,
        faction: String,
        location: String,
        body: String,
        commodity: String,
        progress: f32,
        delivered: u32,
        required: u32,
        remaining: u32,
        spawned_at: u64,
        position: (f32, f32),
    }

    let mut rows: Vec<Row> = sim
        .store
        .world
        .query::<&ConstructionSite>()
        .iter()
        .map(|(_e, s)| Row {
            id: s.id.clone(),
            name: s.name.clone(),
            facility_type: s.facility_type.clone(),
            faction: s.faction_id.clone(),
            location: s.location_name.clone(),
            body: s.body_id.clone(),
            commodity: s.commodity.as_str().to_string(),
            progress: s.progress(),
            delivered: s.progress_delivered,
            required: s.progress_required,
            remaining: s.remaining(),
            spawned_at: s.spawned_at_tick,
            position: s.position,
        })
        .collect();

    // Sort by progress descending — closest-to-done jumps to the top,
    // the "almost-there" builds are the most interesting.
    rows.sort_by(|a, b| {
        b.progress
            .partial_cmp(&a.progress)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let total = rows.len();

    egui::Window::new(format!("Construction · {total}"))
        .id(egui::Id::new("construction_window"))
        .default_width(860.0)
        .default_height(420.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.label(
                egui::RichText::new(
                    "Pending construction sites. Ships delivering their commodity \
                     to the target location accrue progress; at 100% the site \
                     materialises into a real facility.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
            ui.separator();

            if total == 0 {
                ui.label(
                    egui::RichText::new("(no construction sites)")
                        .italics()
                        .color(theme::TEXT_DIM),
                );
                return;
            }

            // Helper closure: dim caption column for the per-site
            // grids. Same `key` pattern the perf panel uses.
            let key = |s: &str| egui::RichText::new(s).color(theme::TEXT_DIM);

            egui::ScrollArea::vertical().show(ui, |ui| {
                for r in &rows {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(egui::RichText::new(&r.name).strong());
                            ui.label(
                                egui::RichText::new(format!("({})", r.facility_type))
                                    .small()
                                    .color(theme::TEXT_DIM),
                            );
                            ui.with_layout(
                                egui::Layout::right_to_left(egui::Align::Center),
                                |ui| {
                                    if ui.button("Focus").clicked() {
                                        let (x, y) = r.position;
                                        focus_req.0 = Some(Vec3::new(
                                            x * SCALE_FACTOR,
                                            0.0,
                                            y * SCALE_FACTOR,
                                        ));
                                    }
                                },
                            );
                        });
                        egui::Grid::new(format!("site_grid_{}", r.id))
                            .num_columns(2)
                            .spacing([12.0, 2.0])
                            .show(ui, |ui| {
                                ui.label(key("Faction"));
                                ui.label(&r.faction);
                                ui.end_row();
                                ui.label(key("Body / location"));
                                ui.label(format!("{} · {}", r.body, r.location));
                                ui.end_row();
                                ui.label(key("Commodity"));
                                ui.label(&r.commodity);
                                ui.end_row();
                                ui.label(key("Spawned at tick"));
                                ui.label(
                                    egui::RichText::new(format!("{}", r.spawned_at)).monospace(),
                                );
                                ui.end_row();
                            });
                        // Progress: SUCCESS once it crosses 50%, WARN
                        // 25-50%, DANGER below — the early-stage sites
                        // need attention to find a fulfilling ship.
                        let pct = r.progress * 100.0;
                        let bar_text = format!(
                            "{} / {} ({}% — {} left)",
                            r.delivered, r.required, pct as u32, r.remaining,
                        );
                        // ProgressBar wants a concrete desired width;
                        // f32::INFINITY trips egui 0.29's
                        // !max_rect.any_nan() assertion the moment a
                        // parent layout subtracts INFINITY-INFINITY.
                        // Pull the live available width instead.
                        let bar_width = ui.available_width().max(120.0);
                        ui.add(
                            egui::ProgressBar::new(r.progress)
                                .text(
                                    egui::RichText::new(bar_text)
                                        .monospace()
                                        .color(theme::status_color(pct, (50.0, 25.0))),
                                )
                                .fill(theme::status_color(pct, (50.0, 25.0)))
                                .desired_width(bar_width),
                        );
                    });
                }
            });
        });

    state.open = open;
}

// =============================================================================
// Minimap
// =============================================================================
//
// Top-down overview of the galaxy: bodies as medium dots, ships as
// tiny dots, a crosshair at the camera focus. Bounds auto-fit to the
// body cluster each frame with a 10% margin so systems at the edge
// aren't clipped. Click anywhere on the minimap to recenter the
// orbit camera on that universe position — cheap navigation.

#[derive(Resource, Default)]
struct MinimapState {
    open: bool,
}

fn minimap_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<MinimapState>,
    camera_q: Query<&OrbitCamera>,
    mut focus_req: ResMut<CameraFocusRequest>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::ship::{ShipIdentity, ShipPosition};

    let mut open = state.open;
    if !open {
        return;
    }

    // Fit to body extents; bodies are the stable anchors. Ships can
    // drift off-map (distant explorers) but the minimap is about the
    // galactic structure, not ship tracking.
    let world = &sim.store.world;
    let body_positions: Vec<(String, (f32, f32))> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    if body_positions.is_empty() {
        state.open = open;
        return;
    }

    let (mut min_x, mut max_x, mut min_y, mut max_y) = (
        f32::INFINITY,
        f32::NEG_INFINITY,
        f32::INFINITY,
        f32::NEG_INFINITY,
    );
    for (_, (x, y)) in &body_positions {
        min_x = min_x.min(*x);
        max_x = max_x.max(*x);
        min_y = min_y.min(*y);
        max_y = max_y.max(*y);
    }
    // 10% margin so dots at the extrema don't render on the frame.
    let span_x = (max_x - min_x).max(1.0);
    let span_y = (max_y - min_y).max(1.0);
    let pad_x = span_x * 0.1;
    let pad_y = span_y * 0.1;
    min_x -= pad_x;
    max_x += pad_x;
    min_y -= pad_y;
    max_y += pad_y;

    egui::Window::new("Map")
        .anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-12.0, -12.0))
        .default_width(260.0)
        .default_height(260.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            // Reserve a square plotting area; painter draws into the
            // allocated rect. 220×220 leaves room for the title bar.
            let (rect, response) =
                ui.allocate_exact_size(egui::vec2(220.0, 220.0), egui::Sense::click());
            let painter = ui.painter_at(rect);
            // Background panel so the minimap reads as its own surface.
            painter.rect_filled(rect, 2.0, theme::PANEL_BG);

            let to_screen = |ux: f32, uy: f32| -> egui::Pos2 {
                let nx = (ux - min_x) / (max_x - min_x);
                let ny = (uy - min_y) / (max_y - min_y);
                egui::pos2(
                    rect.left() + nx * rect.width(),
                    rect.top() + ny * rect.height(),
                )
            };

            // Ships first so bodies overlay them.
            for (_e, (_, pos)) in world.query::<(&ShipIdentity, &ShipPosition)>().iter() {
                let (x, y) = pos.position;
                if x < min_x || x > max_x || y < min_y || y > max_y {
                    continue;
                }
                painter.circle_filled(to_screen(x, y), 1.0, theme::TEXT_DIM);
            }

            // Bodies: bigger dots, PRIMARY-tinted to share the
            // holographic palette with the rest of the HUD.
            for (_, (x, y)) in &body_positions {
                painter.circle_filled(to_screen(*x, *y), 3.0, theme::PRIMARY);
            }

            // Camera focus crosshair — convert world-space back to
            // universe coords by dividing out SCALE_FACTOR.
            if let Ok(orbit) = camera_q.get_single() {
                let ux = orbit.focus.x / SCALE_FACTOR;
                let uy = orbit.focus.z / SCALE_FACTOR;
                if ux >= min_x && ux <= max_x && uy >= min_y && uy <= max_y {
                    let p = to_screen(ux, uy);
                    let color = theme::WARN;
                    painter.line_segment(
                        [egui::pos2(p.x - 6.0, p.y), egui::pos2(p.x + 6.0, p.y)],
                        egui::Stroke::new(1.5, color),
                    );
                    painter.line_segment(
                        [egui::pos2(p.x, p.y - 6.0), egui::pos2(p.x, p.y + 6.0)],
                        egui::Stroke::new(1.5, color),
                    );
                }
            }

            // Click-to-recenter. Convert the clicked point back to
            // universe coords, then into world coords for the focus
            // request. Y-flip not needed — the map is top-down with
            // universe y mapped to screen y.
            if response.clicked() {
                if let Some(click) = response.interact_pointer_pos() {
                    let nx = ((click.x - rect.left()) / rect.width()).clamp(0.0, 1.0);
                    let ny = ((click.y - rect.top()) / rect.height()).clamp(0.0, 1.0);
                    let ux = min_x + nx * (max_x - min_x);
                    let uy = min_y + ny * (max_y - min_y);
                    focus_req.0 = Some(Vec3::new(ux * SCALE_FACTOR, 0.0, uy * SCALE_FACTOR));
                }
            }

            ui.label(
                egui::RichText::new(
                    "click to recenter · dots: ships · larger: bodies · cross: camera",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
        });

    state.open = open;
}

// =============================================================================
// Body labels overlay
// =============================================================================
//
// Projects each body's world position to screen space and draws its
// name as an egui label. Helps with orientation at zoomed-out scales
// where the body meshes are just dots. Toggleable from the top bar
// so users who'd rather see a clean scene can hide them.

#[derive(Resource)]
struct BodyLabelsState {
    show: bool,
}

impl Default for BodyLabelsState {
    // Labels ON by default — first-time users benefit more from
    // orientation hints than they lose to the small visual clutter.
    fn default() -> Self {
        Self { show: true }
    }
}

/// Top-of-screen Y below which labels are allowed to render. Above
/// this they'd overlap the always-on top-bar chrome. Bevy_egui's
/// layer ordering doesn't actually push Background-ordered Areas
/// below TopBottomPanels in practice (verified via screenshot in
/// 4bg) — clipping by Y is the reliable fix.
///
/// `available_rect().top()` returns the bottom of all top-anchored
/// panels claimed so far this frame. Requires the calling system
/// to run AFTER the top-bar shows — the chain-2 systems explicitly
/// `.after(top_bar)` for this reason (see UiPlugin::build).
fn label_min_y(ctx: &egui::Context) -> f32 {
    ctx.available_rect().top()
}

fn body_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};

    if !state.show {
        return;
    }

    let Ok((camera, cam_xf)) = camera_q.get_single() else {
        return;
    };

    let world = &sim.store.world;
    let entries: Vec<(String, Vec3)> = world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| {
            let (x, y) = orbit.universe_position();
            (
                id.name.clone(),
                Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
            )
        })
        .collect();

    // Use a transparent, non-interactive overlay area so labels
    // paint on top without eating clicks or blocking egui's
    // tooltip logic.
    let ctx = ctx.ctx_mut();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("body_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                // Skip bodies behind the camera. world_to_viewport
                // returns None for off-screen or behind-camera —
                // treat that as "don't draw".
                let Some(screen) = camera.world_to_viewport(cam_xf, pos) else {
                    continue;
                };
                // Offset label a bit above the body so it doesn't
                // occlude the sphere.
                let anchor = egui::pos2(screen.x, screen.y - 12.0);
                if anchor.y < min_y {
                    continue;
                }
                painter.text(
                    anchor,
                    egui::Align2::CENTER_BOTTOM,
                    &name,
                    egui::FontId::proportional(11.0),
                    theme::TEXT,
                );
            }
        });
}

/// Zoom thresholds (orbit camera distance, world units) at which
/// each label tier turns ON. Bodies are always-on (orientation
/// anchor, ~30 of them). Facilities + construction sites only
/// matter when the user is close enough to make station-level
/// decisions. Ships only appear when the user is right on top of
/// a single hull — their density would carpet the screen at any
/// wider zoom. Tuned against `OrbitCamera::initial()` distance
/// (~3500 wu galactic overview) and the per-system inner-planet
/// scale (~500 wu).
const FACILITY_LABEL_MAX_DIST: f32 = 500.0;
const CONSTRUCTION_LABEL_MAX_DIST: f32 = 500.0;
const SHIP_LABEL_MAX_DIST: f32 = 75.0;

/// Construction-site labels overlay. Same pattern as
/// `body_labels_panel`: project each site's universe position to
/// screen and draw "<name> · <pct>%" above the gizmo. Gated on the
/// "Labels" toggle AND zoom — only shows when the user is close
/// enough that the percentage actually helps (<1500 wu).
#[allow(clippy::type_complexity)]
fn construction_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform, &OrbitCamera), With<Camera3d>>,
) {
    use sim_core::agents::construction::ConstructionSite;
    if !state.show {
        return;
    }
    let Ok((camera, cam_xf, orbit)) = camera_q.get_single() else {
        return;
    };
    if orbit.distance > CONSTRUCTION_LABEL_MAX_DIST {
        return;
    }

    let entries: Vec<(String, f32, Vec3)> = sim
        .store
        .world
        .query::<&ConstructionSite>()
        .iter()
        .map(|(_e, site)| {
            let (x, y) = site.position;
            let world = Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR);
            (site.name.clone(), site.progress(), world)
        })
        .collect();

    let ctx = ctx.ctx_mut();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("construction_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, prog, pos) in entries {
                let Some(screen) = camera.world_to_viewport(cam_xf, pos) else {
                    continue;
                };
                let name_y = screen.y - 26.0;
                if name_y < min_y {
                    continue;
                }
                painter.text(
                    egui::pos2(screen.x, name_y),
                    egui::Align2::CENTER_BOTTOM,
                    &name,
                    egui::FontId::proportional(11.0),
                    theme::TEXT_DIM,
                );
                let pct = (prog * 100.0).round() as u32;
                painter.text(
                    egui::pos2(screen.x, screen.y - 14.0),
                    egui::Align2::CENTER_BOTTOM,
                    format!("{pct}%"),
                    egui::FontId::proportional(11.0),
                    theme::status_color(prog * 100.0, (50.0, 25.0)),
                );
            }
        });
}

/// Facility name labels overlay. Walks every facility, projects to
/// screen, draws name above the icon. Zoom-gated against
/// `FACILITY_LABEL_MAX_DIST` so the user gets clean orbits at
/// galactic scale and station names when they zoom into a system.
#[allow(clippy::type_complexity)]
fn facility_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform, &OrbitCamera), With<Camera3d>>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};
    use sim_core::agents::facility::{FacilityIdentity, FacilityLocation};
    if !state.show {
        return;
    }
    let Ok((camera, cam_xf, orbit)) = camera_q.get_single() else {
        return;
    };
    if orbit.distance > FACILITY_LABEL_MAX_DIST {
        return;
    }

    // Resolve each facility's world position via its body orbit +
    // facility_offset_position helper — same math the renderer
    // uses to plant facility scenes.
    let body_pos: std::collections::HashMap<String, (f32, f32)> = sim
        .store
        .world
        .query::<(&BodyIdentity, &BodyOrbit)>()
        .iter()
        .map(|(_e, (id, orbit))| (id.body_id.clone(), orbit.universe_position()))
        .collect();

    let entries: Vec<(String, Vec3)> = sim
        .store
        .world
        .query::<(&FacilityIdentity, &FacilityLocation)>()
        .iter()
        .filter_map(|(_e, (id, _loc))| {
            let body = body_pos.get(&id.body_id).copied()?;
            let (fx, fy) = sim_core::agents::facility::facility_offset_position(body, &id.id);
            Some((
                id.name.clone(),
                Vec3::new(fx * SCALE_FACTOR, 0.5, fy * SCALE_FACTOR),
            ))
        })
        .collect();

    let ctx = ctx.ctx_mut();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("facility_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                let Some(screen) = camera.world_to_viewport(cam_xf, pos) else {
                    continue;
                };
                let anchor = egui::pos2(screen.x, screen.y - 14.0);
                if anchor.y < min_y {
                    continue;
                }
                painter.text(
                    anchor,
                    egui::Align2::CENTER_BOTTOM,
                    &name,
                    egui::FontId::proportional(10.0),
                    theme::TEXT_DIM,
                );
            }
        });
}

/// Ship name labels overlay. Tightest zoom gate of the three —
/// labels appear only when the camera is right on a ship cluster
/// (<200 wu). At any wider zoom the density would carpet the
/// screen with overlapping text.
#[allow(clippy::type_complexity)]
fn ship_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform, &OrbitCamera), With<Camera3d>>,
) {
    use sim_core::agents::ship::{ShipIdentity, ShipPosition};
    if !state.show {
        return;
    }
    let Ok((camera, cam_xf, orbit)) = camera_q.get_single() else {
        return;
    };
    if orbit.distance > SHIP_LABEL_MAX_DIST {
        return;
    }

    let entries: Vec<(String, Vec3)> = sim
        .store
        .world
        .query::<(&ShipIdentity, &ShipPosition)>()
        .iter()
        .map(|(_e, (id, pos))| {
            let (x, y) = pos.position;
            (
                id.name.clone(),
                Vec3::new(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR),
            )
        })
        .collect();

    let ctx = ctx.ctx_mut();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("ship_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                let Some(screen) = camera.world_to_viewport(cam_xf, pos) else {
                    continue;
                };
                let anchor = egui::pos2(screen.x, screen.y - 10.0);
                if anchor.y < min_y {
                    continue;
                }
                painter.text(
                    anchor,
                    egui::Align2::CENTER_BOTTOM,
                    &name,
                    egui::FontId::proportional(10.0),
                    theme::TEXT_DIM,
                );
            }
        });
}

// =============================================================================
// Events ticker
// =============================================================================
//
// Scrollable list over the bounded EventsLog ring. Each row shows
// tick, kind, and a short human summary built from the event json.
// Filter by kind substring; follow-tail toggle sticks to newest.
// Matches the Godot events_ticker.gd pattern without trying to
// exactly replicate every column — parity is "can you see what just
// happened in the economy".

#[derive(Resource)]
struct EventsState {
    open: bool,
    filter: String,
    follow_tail: bool,
}

impl Default for EventsState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("events") || s == "all")
            .unwrap_or(false);
        Self {
            open: auto_open,
            filter: String::new(),
            follow_tail: false,
        }
    }
}

fn events_panel(mut ctx: EguiContexts, events: Res<EventsLog>, mut state: ResMut<EventsState>) {
    let mut open = state.open;
    let mut filter = state.filter.clone();
    let mut follow_tail = state.follow_tail;
    if !open {
        return;
    }

    let filter_lc = filter.to_lowercase();
    // Collect matching entries newest-first for display. The
    // underlying ring is oldest-at-front so we iterate in reverse.
    let filtered: Vec<(&u64, &serde_json::Value)> = events
        .0
        .iter()
        .rev()
        .map(|(t, v)| (t, v))
        .filter(|(_, v)| {
            if filter_lc.is_empty() {
                return true;
            }
            let kind = v.get("kind").and_then(|k| k.as_str()).unwrap_or("");
            kind.to_lowercase().contains(&filter_lc)
                || v.to_string().to_lowercase().contains(&filter_lc)
        })
        .take(500) // panel cap — ring is larger
        .collect();

    let total = events.0.len();
    let shown = filtered.len();

    egui::Window::new(format!("Events · {shown}/{total}"))
        .id(egui::Id::new("events_window"))
        .default_width(640.0)
        .default_height(420.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.horizontal(|ui| {
                ui.label("filter kind:");
                ui.text_edit_singleline(&mut filter);
                ui.separator();
                ui.checkbox(&mut follow_tail, "follow tail");
            });
            ui.separator();

            // Panel renders newest-first so scrolling the ScrollArea
            // down goes into the past. The "follow tail" toggle is
            // informational only — the newest event always sits at
            // the top of the list, so no scroll positioning needed.
            // Kept as a checkbox for the user to indicate intent.
            let _ = follow_tail;
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    egui::Grid::new("events_grid")
                        .striped(true)
                        .num_columns(3)
                        .spacing([10.0, 3.0])
                        .show(ui, |ui| {
                            for header in ["Tick", "Kind", "Detail"] {
                                ui.label(
                                    egui::RichText::new(header).strong().color(theme::TEXT_DIM),
                                );
                            }
                            ui.end_row();

                            for (tick, v) in filtered {
                                let kind = v.get("kind").and_then(|k| k.as_str()).unwrap_or("?");
                                let summary = event_summary(v);
                                ui.label(
                                    egui::RichText::new(format!("{tick}"))
                                        .monospace()
                                        .color(theme::TEXT_DIM),
                                );
                                ui.colored_label(event_kind_color(kind), kind);
                                ui.label(egui::RichText::new(summary).color(theme::TEXT_DIM));
                                ui.end_row();
                            }
                        });
                });
        });

    state.open = open;
    state.filter = filter;
    state.follow_tail = follow_tail;
}

fn event_kind_color(kind: &str) -> egui::Color32 {
    // Theme palette buckets by subject. Nothing load-bearing — just
    // visual scan help. Unknown kinds fall through to neutral TEXT.
    match kind {
        "ship_docked" | "ship_spawned" | "ship_leveled_up" | "ship_refitted" | "treaty_changed" => {
            theme::PRIMARY
        }
        "ship_decommissioned" | "ship_destroyed_with_cargo" | "contract_expired" => theme::DANGER,
        "contract_delivered"
        | "crew_mission_completed"
        | "passengers_arrived"
        | "market_recovered"
        | "facility_recovered"
        | "construction_completed" => theme::SUCCESS,
        "market_crisis" | "facility_starving" | "facility_abandoned" => theme::WARN,
        _ => theme::TEXT,
    }
}

fn event_summary(v: &serde_json::Value) -> String {
    // Build a short, scan-readable summary from the most common
    // fields. Falls back to the kind if we can't compose anything
    // meaningful. Trying to be exhaustive is a losing game since
    // new event kinds keep getting added; a few high-value fields
    // cover the bulk of output volume.
    let get = |k: &str| {
        v.get(k)
            .map(|x| x.to_string().trim_matches('"').to_string())
    };

    let pieces: Vec<String> = [
        "ship_id",
        "id",
        "location",
        "facility_id",
        "commodity",
        "reason",
        "a",
        "b",
        "to",
        "from",
    ]
    .iter()
    .filter_map(|k| get(k).map(|val| format!("{k}={val}")))
    .collect();
    if pieces.is_empty() {
        return v.to_string();
    }
    pieces.join(" · ")
}

// =============================================================================
// Keyboard shortcuts
// =============================================================================
//
// Global shortcuts that wire into the UI state:
//   * Spacebar       → toggle Sim.running (pause/resume)
//   * Escape         → clear Selected{Ship,Facility}
//
// Skips when egui owns the keyboard (a filter text box is focused,
// etc.) so typing in a panel doesn't accidentally pause the sim.

#[allow(clippy::too_many_arguments)]
fn keyboard_shortcuts(
    keys: Res<ButtonInput<KeyCode>>,
    mut sim: ResMut<Sim>,
    mut menu: ResMut<PauseMenuState>,
    mut help: ResMut<HelpState>,
    mut egui_ctx: EguiContexts,
) {
    // When egui is capturing keyboard input (an editable text
    // widget has focus), don't fire shortcuts — typing "pause" in a
    // filter box would otherwise trigger pause on the 'p' the user
    // just wanted to search for.
    if egui_ctx.ctx_mut().wants_keyboard_input() {
        return;
    }
    // Suppress Spacebar pause-toggle while the pause menu is open —
    // otherwise Space would flip sim.running independently of the
    // menu's internal `was_running` bookkeeping, leaving the user
    // staring at a "Paused" overlay over a running sim.
    if keys.just_pressed(KeyCode::Space) && !menu.open {
        sim.running = !sim.running;
    }
    // `?` (Slash, with or without Shift) or `H` toggles the help
    // popup. egui consumes Shift natively when ShiftLeft is held;
    // we just react to either key landing.
    if keys.just_pressed(KeyCode::Slash) || keys.just_pressed(KeyCode::KeyH) {
        help.open = !help.open;
    }
    if keys.just_pressed(KeyCode::Escape) {
        // Esc toggles the pause menu. Selection clear lives on the
        // top-bar "✕ Clear" chip — separating the two stops Esc from
        // doing two unrelated things based on selection state.
        if menu.open {
            menu.open = false;
            sim.running = menu.was_running;
        } else {
            menu.open = true;
            menu.was_running = sim.running;
            sim.running = false;
        }
    }
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

/// Help popup. Toggled by `?` / `H` keys (see `keyboard_shortcuts`)
/// or by clicking the `?` button on the pause menu. Lists the
/// keyboard + mouse hotkeys as a single egui grid.
#[derive(Resource, Default)]
struct HelpState {
    open: bool,
}

fn help_panel(mut ctx: EguiContexts, mut help: ResMut<HelpState>) {
    let mut open = help.open;
    if !open {
        return;
    }
    egui::Window::new("Help · Hotkeys")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(380.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            egui::Grid::new("help_keys")
                .num_columns(2)
                .striped(true)
                .spacing([12.0, 4.0])
                .show(ui, |ui| {
                    let key =
                        |label: &str| egui::RichText::new(label).monospace().color(theme::PRIMARY);
                    let row = |ui: &mut egui::Ui, k: &str, desc: &str| {
                        ui.label(key(k));
                        ui.label(desc);
                        ui.end_row();
                    };
                    ui.label(theme::section_header("Sim control"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Space", "Pause / resume the sim");
                    row(ui, "Esc", "Open / close the pause menu");
                    ui.label(theme::section_header("Camera"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Left-drag", "Orbit around focus point");
                    row(ui, "Middle-drag", "Orbit around focus point");
                    row(ui, "Right-drag", "Pan focus across plane");
                    row(ui, "Shift-Left-drag", "Pan focus across plane");
                    row(ui, "WASD", "Pan focus relative to camera");
                    row(ui, "Scroll / Pinch", "Zoom in / out");
                    ui.label(theme::section_header("Selection"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "Left-click", "Select ship / facility");
                    row(
                        ui,
                        "Right-click",
                        "Context menu (Inspect / Follow / POV / Destroy)",
                    );
                    row(ui, "✕ Clear (top bar)", "Deselect");
                    ui.label(theme::section_header("Misc"));
                    ui.label("");
                    ui.end_row();
                    row(ui, "F12", "Screenshot to /tmp/bevy_screenshot.png");
                    row(ui, "?  /  H", "Show this help popup");
                });
        });
    help.open = open;
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
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut sim: ResMut<Sim>,
    mut options: ResMut<OptionsState>,
    mut saves: ResMut<SaveListState>,
    mut exit: EventWriter<AppExit>,
) {
    egui::Area::new(egui::Id::new("main_menu"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx.ctx_mut(), |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new("SPACE SIMULATOR")
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
                            egui::RichText::new("Start").size(16.0).color(theme::PRIMARY),
                        ),
                    )
                    .clicked()
                {
                    next_state.set(crate::AppState::InGame);
                    // Resume the sim — it was forced false on entry
                    // to MainMenu (or never started, on a fresh boot).
                    sim.running = true;
                }
                ui.add_space(4.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Load Game"))
                    .on_hover_text(
                        "Browse Save-As snapshots stored next to the binary.",
                    )
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
                        egui::Button::new(
                            egui::RichText::new("Quit").color(theme::DANGER),
                        ),
                    )
                    .clicked()
                {
                    exit.send(AppExit::Success);
                }
                ui.add_space(8.0);
            });
        });
}

/// Save-list browser. Scans the directory containing the executable
/// (or current working directory in dev) for `*.db` files, lists
/// each as a row with Load + Delete buttons. The active sim DB
/// (default name `sim.db`) is filtered out so users can't blow it
/// away by accident — that path stays reserved for "fresh boot".
///
/// Load is currently a stub that logs the picked path; the
/// implementation needs an in-process sim teardown + reload pass
/// (rebuild AgentStore, despawn render entities, re-run
/// `load_world` with the chosen path), which is its own bundle.
/// Delete is fully wired — `std::fs::remove_file` plus list
/// refresh.
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
        // Skip the active DB + sqlite sidecar files. Also skip
        // anything not ending in .db.
        if name == "sim.db" || !name.ends_with(".db") {
            continue;
        }
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
        });
    }
    out.sort_by(|a, b| b.modified_iso.cmp(&a.modified_iso));
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
        31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    ];
    let mut m: usize = 0;
    while m < 12 && days >= mdays[m] {
        days -= mdays[m];
        m += 1;
    }
    (y, (m + 1) as u32, (days + 1) as u32)
}

fn save_list_panel(mut ctx: EguiContexts, mut state: ResMut<SaveListState>) {
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
                ui.with_layout(
                    egui::Layout::right_to_left(egui::Align::Center),
                    |ui| {
                        if ui.small_button("Refresh").clicked() {
                            want_refresh = true;
                        }
                    },
                );
            });
            ui.separator();
            if state.saves.is_empty() {
                ui.label(
                    egui::RichText::new(
                        "No save snapshots found next to the binary. \
                         Use the pause menu's Save As… to create one.",
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
                                ui.label(&save.name);
                                ui.label(
                                    egui::RichText::new(&save.modified_iso)
                                        .small()
                                        .monospace()
                                        .color(theme::TEXT_DIM),
                                );
                                ui.label(
                                    egui::RichText::new(format!(
                                        "{} KB",
                                        save.size_kb
                                    ))
                                    .small()
                                    .monospace(),
                                );
                                ui.horizontal(|ui| {
                                    if ui
                                        .small_button("Load")
                                        .on_hover_text(
                                            "Load this save into the running \
                                             sim. (Stub: in-process reload \
                                             lands in a follow-up bundle.)",
                                        )
                                        .clicked()
                                    {
                                        want_load = Some(save.path.clone());
                                    }
                                    if ui
                                        .small_button(
                                            egui::RichText::new("Delete")
                                                .color(theme::DANGER),
                                        )
                                        .on_hover_text(
                                            "Permanently delete this snapshot \
                                             from disk. No confirmation.",
                                        )
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
                state.last_scan = None;
            }
            Err(e) => {
                error!("client_bevy: failed to delete {}: {}", p.display(), e);
            }
        }
    }
    if let Some(p) = want_load {
        // TODO(4bs): in-process sim teardown + reload from `p`.
        // For now log so the wiring's testable; the user can swap
        // the file by exiting and copying it over sim.db.
        info!("client_bevy: load requested for {} (in-process reload TBD)", p.display());
    }
    state.open = open;
}

/// Options window — audio + display settings. Toggled from the
/// pause menu's "Options" button (and, in a later bundle, from the
/// main menu). State is just `open`; the actual settings live on
/// `crate::audio::AudioSettings` etc. so they stay valid when the
/// window is closed.
#[derive(Resource, Default)]
struct OptionsState {
    open: bool,
}

fn options_panel(
    mut ctx: EguiContexts,
    mut state: ResMut<OptionsState>,
    mut audio: ResMut<crate::audio::AudioSettings>,
) {
    let mut open = state.open;
    if !open {
        return;
    }
    egui::Window::new("Options")
        .id(egui::Id::new("options_window"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(360.0)
        .open(&mut open)
        .show(ctx.ctx_mut(), |ui| {
            ui.add_space(4.0);
            ui.label(theme::section_header("Audio"));
            ui.add_space(4.0);

            // Bevy's AudioSink::set_volume is linear gain; volumes
            // 0..=1 map directly. Capping the sliders at 1.0 keeps
            // the user from blowing out — boost beyond unity gain
            // requires HDR mixing we don't ship.
            egui::Grid::new("options_audio")
                .num_columns(2)
                .spacing([12.0, 8.0])
                .show(ui, |ui| {
                    ui.label(theme::caption("Music"));
                    ui.add(
                        egui::Slider::new(&mut audio.music_volume, 0.0..=1.0)
                            .show_value(true)
                            .fixed_decimals(2),
                    );
                    ui.end_row();

                    ui.label(theme::caption("SFX"));
                    ui.add(
                        egui::Slider::new(&mut audio.sfx_volume, 0.0..=1.0)
                            .show_value(true)
                            .fixed_decimals(2),
                    );
                    ui.end_row();
                });

            ui.add_space(4.0);
            ui.separator();
            ui.add_space(2.0);
            ui.label(
                egui::RichText::new(
                    "Music applies live; SFX applies on the next one-shot.",
                )
                .small()
                .italics()
                .color(theme::TEXT_DIM),
            );
        });
    state.open = open;
}

/// Modal-ish "Pause" menu. Esc toggles it (see `keyboard_shortcuts`).
/// While open the sim is forced paused; closing the menu restores
/// the prior running state. Buttons: Resume, Save As, Quit. Save is
/// folded into Save As since the embedded client has no live
/// persistence worker — every save is effectively a snapshot copy.
#[derive(Resource, Default)]
struct PauseMenuState {
    open: bool,
    /// Sim's `running` state at the moment the menu was opened, so
    /// closing the menu restores that state instead of always
    /// resuming.
    was_running: bool,
}

#[allow(clippy::too_many_arguments)]
fn pause_menu(
    mut ctx: EguiContexts,
    mut menu: ResMut<PauseMenuState>,
    mut sim: ResMut<Sim>,
    mut save_req: ResMut<crate::sim::SaveAsRequest>,
    mut help: ResMut<HelpState>,
    mut options: ResMut<OptionsState>,
    mut next_state: ResMut<NextState<crate::AppState>>,
    mut exit: EventWriter<AppExit>,
) {
    if !menu.open {
        return;
    }
    egui::Window::new("Paused")
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .collapsible(false)
        .resizable(false)
        .default_width(280.0)
        .show(ctx.ctx_mut(), |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(6.0);
                ui.label(
                    egui::RichText::new("Game paused")
                        .strong()
                        .size(16.0)
                        .color(theme::PRIMARY),
                );
                ui.add_space(8.0);
                let btn_size = egui::vec2(220.0, 32.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Resume (Esc)"))
                    .clicked()
                {
                    menu.open = false;
                    sim.running = menu.was_running;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Save As…"))
                    .on_hover_text(
                        "Write a timestamped VACUUM INTO snapshot of sim.db. \
                         Embedded client has no persistence worker yet, so the \
                         snapshot reflects the load tick rather than live state.",
                    )
                    .clicked()
                {
                    save_req.0 = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Options"))
                    .on_hover_text("Audio + display settings.")
                    .clicked()
                {
                    options.open = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Help (?)"))
                    .on_hover_text("Show the hotkey reference popup.")
                    .clicked()
                {
                    help.open = true;
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(btn_size, egui::Button::new("Return to Main Menu"))
                    .on_hover_text(
                        "Pause the sim and go back to the title screen. \
                         The world stays loaded — Start resumes from here.",
                    )
                    .clicked()
                {
                    sim.running = false;
                    menu.open = false;
                    next_state.set(crate::AppState::MainMenu);
                }
                ui.add_space(2.0);
                if ui
                    .add_sized(
                        btn_size,
                        egui::Button::new(egui::RichText::new("Quit").color(theme::DANGER)),
                    )
                    .on_hover_text("Close the window.")
                    .clicked()
                {
                    exit.send(AppExit::Success);
                }
                ui.add_space(6.0);
            });
        });
}
