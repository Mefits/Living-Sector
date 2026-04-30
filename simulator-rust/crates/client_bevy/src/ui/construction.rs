//! Construction sites panel.
//!
//! One row per pending Phase-19c construction site (a chronic-shortage
//! demand-analyzer build that ships are delivering cargo to). Each
//! row shows the sponsoring faction, target body/location, commodity
//! consumed per delivery, and a tinted progress bar (DANGER/WARN/
//! SUCCESS by completion %). "Focus" jumps the camera to the site's
//! universe position. Sorted progress-descending so the
//! closest-to-done sites surface first.
//!
//! State: [`ConstructionState`] (open flag — auto-open via
//! `CLIENT_BEVY_OPEN_PANELS=construction|all`).
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::camera::CameraFocusRequest;
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct ConstructionState {
    pub open: bool,
}

impl Default for ConstructionState {
    fn default() -> Self {
        let auto_open = std::env::var("CLIENT_BEVY_OPEN_PANELS")
            .map(|s| s.contains("construction") || s == "all")
            .unwrap_or(false);
        Self { open: auto_open }
    }
}

pub(super) fn construction_panel(
    mut ctx: EguiContexts,
    mut sim: ResMut<Sim>,
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

    let mut rows: Vec<Row> = {
        let mut q = sim.store.world.query::<&ConstructionSite>();
        q.iter(&sim.store.world)
            .map(|s| Row {
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
            .collect()
    };

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
        .show(ctx.ctx_mut().unwrap(), |ui| {
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
