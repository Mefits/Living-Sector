//! Top-bar chrome — two horizontally-stacked TopBottomPanels.
//!
//! The combined controls + panel-toggle set blew through Bevy's
//! 16-param SystemParam tuple cap, so the top bar is split into two
//! systems that render adjacent egui::TopBottomPanels:
//!
//! * [`top_bar_controls`] — left chunk: pause/play, world-speed
//!   combo, tick readout, reset-view, save-as, +Ship / +Fac admin
//!   spawn buttons, Menu, `?` help. Right-aligned chips for current
//!   selection + camera-follow with one-click clears.
//! * [`top_bar`] — right chunk: every panel-toggle button (Perf,
//!   Ships, Contracts, Factions, Markets, Pops, Facilities,
//!   Retired, Construction, Map, Labels, Events). Each toggle
//!   shows its panel's `open` flag via egui's `selected` styling
//!   plus an optional `(count)` next to the label.
//!
//! Visuals come from [`holo_chrome_frame`] (opaque navy fill +
//! PRIMARY-tinted edge stroke) and [`paint_holo_chrome_overlay`]
//! (vertical-gradient overlay painted into a Foreground LayerId so
//! it sits above the panel fill but below interactive widget
//! content).
//!
//! [`icon_toggle_with_tip`] is the per-button helper used by the
//! panel-toggle row so every entry has the same shape (icon + label
//! + optional count + selected highlight + hover tooltip).
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::construction::ConstructionState;
use super::contracts::ContractsState;
use super::events::EventsState;
use super::facility::{FacilityListState, SelectedFacility};
use super::factions::FactionsState;
use super::help::HelpState;
use super::labels::BodyLabelsState;
use super::markets::MarketsState;
use super::menus::PauseMenuState;
use super::minimap::MinimapState;
use super::perf::PerfStats;
use super::populations::PopulationsState;
use super::retirements::RetirementsState;
use super::ship_list::{SelectedShip, ShipListState};
use super::spawn_dialogs::{AddFacilityDialogState, AddShipDialogState};
use super::{icons, theme};
use crate::camera::CameraResetRequest;
use crate::sim::{EventsLog, Retirements, Sim};

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
        // egui 0.31 (bevy_egui 0.34): Margin fields are i8 (was f32);
        // Frame::rounding renamed to Frame::corner_radius and uses
        // CornerRadius (not Rounding).
        inner_margin: egui::Margin::symmetric(8, 4),
        outer_margin: egui::Margin::ZERO,
        corner_radius: egui::CornerRadius::ZERO,
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

/// Pause / speed / tick readout / global controls (reset view,
/// save as). Split out from [`top_bar`] because Bevy caps system
/// param tuples at 16 and the combined set blew through that.
#[allow(clippy::too_many_arguments)]
pub(super) fn top_bar_controls(
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
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new("spaceproject").strong());
                ui.separator();
                // Pause / play — icon-only square button. Hover surfaces
                // the action text since the icon alone is unambiguous
                // (▶ play, ⏸ pause).
                let running = sim.running;
                let pp_resp = ui
                    .add(egui::Button::image(if running {
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
    let painter = ctx.ctx_mut().unwrap().layer_painter(egui::LayerId::new(
        egui::Order::Foreground,
        egui::Id::new("top_bar_controls_overlay"),
    ));
    paint_holo_chrome_overlay(&painter, resp_controls.response.rect);
}

#[allow(clippy::too_many_arguments)]
pub(super) fn top_bar(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
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
    let construction_count = {
        let mut q = sim.store.world.query::<&ConstructionSite>();
        q.iter(&sim.store.world).count()
    };
    let resp_panels = egui::TopBottomPanel::top("top_bar_panels")
        .frame(holo_chrome_frame())
        .show(ctx.ctx_mut().unwrap(), |ui| {
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
    let painter = ctx.ctx_mut().unwrap().layer_painter(egui::LayerId::new(
        egui::Order::Foreground,
        egui::Id::new("top_bar_panels_overlay"),
    ));
    paint_holo_chrome_overlay(&painter, resp_panels.response.rect);
}
