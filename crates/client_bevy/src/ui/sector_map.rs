//! Living Sector: read-only strategic map of star systems and territorial control.
//!
//! Deliberately separate from the economy, ship AI, and 3D renderer.
//! Gate lines are built only from real GateLink pairs, never inferred
//! from nearest-neighbor positions. The tinted circles are ownership
//! markers, NOT geopolitical border polygons.

use std::collections::{BTreeSet, HashMap};

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use sim_core::agents::{
    celestial_body::{BodyIdentity, BodyTerritory},
    faction::FactionData,
};

use super::theme;
use crate::camera::CameraFocusRequest;
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct SectorMapState {
    pub open: bool,
    selected: Option<String>,
    zoom: f32,
    pan: egui::Vec2,
}

impl Default for SectorMapState {
    fn default() -> Self {
        Self {
            open: false,
            selected: None,
            zoom: 1.0,
            pan: egui::Vec2::ZERO,
        }
    }
}

struct SystemNode {
    name: String,
    xy: (f32, f32),
    controlling_faction: Option<String>,
    contested: bool,
}

/// Resolves a location pair into two distinct star systems via the
/// body-id mapping. This does not invent trade lanes between nearby stars.
fn gate_connections(
    sim: &Sim,
    body_systems: &HashMap<i64, String>,
) -> BTreeSet<(String, String)> {
    let mut links = BTreeSet::new();
    for (from, to) in &sim.store.gate_pairs {
        let (Some(from_loc), Some(to_loc)) = (
            sim.registry.locations.get(from),
            sim.registry.locations.get(to),
        ) else {
            continue;
        };
        let (Some(a), Some(b)) = (
            body_systems.get(&from_loc.celestial_body_id),
            body_systems.get(&to_loc.celestial_body_id),
        ) else {
            continue;
        };
        if a.eq_ignore_ascii_case(b) {
            continue;
        }
        if a < b {
            links.insert((a.clone(), b.clone()));
        } else {
            links.insert((b.clone(), a.clone()));
        }
    }
    links
}

pub(super) fn sector_map_panel(
    mut ctx: EguiContexts,
    sim: Res<Sim>,
    mut state: ResMut<SectorMapState>,
    mut focus_req: ResMut<CameraFocusRequest>,
    bodies: Query<(&BodyIdentity, Option<&BodyTerritory>)>,
    factions: Query<&FactionData>,
) {
    if !state.open {
        return;
    }

    let body_systems: HashMap<i64, String> = bodies
        .iter()
        .map(|(id, _)| (id.db_id, id.system_name.clone()))
        .collect();
    let disputed_systems: BTreeSet<String> = bodies
        .iter()
        .filter_map(|(id, territory)| {
            territory
                .filter(|t| t.contested)
                .map(|_| id.system_name.to_lowercase())
        })
        .collect();

    let mut nodes: Vec<SystemNode> = sim
        .registry
        .systems
        .values()
        .map(|sys| SystemNode {
            name: sys.name.clone(),
            xy: sys.universe_offset,
            controlling_faction: sim
                .store
                .system_control
                .iter()
                .find(|(name, _)| name.eq_ignore_ascii_case(&sys.name))
                .and_then(|(_, owner)| owner.clone()),
            contested: disputed_systems.contains(&sys.name.to_lowercase()),
        })
        .collect();
    nodes.sort_by(|a, b| a.name.cmp(&b.name));

    let links = gate_connections(&sim, &body_systems);
    let faction_names: HashMap<String, String> = factions
        .iter()
        .map(|f| (f.id.clone(), f.name.clone()))
        .collect();

    let mut open = state.open;
    let mut selected = state.selected.clone();
    let mut zoom = state.zoom;
    let mut pan = state.pan;
    let mut close_after_focus = false;

    egui::Window::new("Sector | Political map")
        .id(egui::Id::new("living_sector_political_map"))
        .default_size(egui::vec2(840.0, 600.0))
        .min_width(530.0)
        .resizable(true)
        .open(&mut open)
        .show(ctx.ctx_mut().unwrap(), |ui| {
            ui.horizontal(|ui| {
                ui.label(format!(
                    "{} systems  |  {} real gate links  |  tick {}",
                    nodes.len(),
                    links.len(),
                    sim.tick
                ));
                ui.separator();
                ui.add(egui::Slider::new(&mut zoom, 0.5..=8.0).text("Zoom"));
                if ui.button("Reset").clicked() {
                    zoom = 1.0;
                    pan = egui::Vec2::ZERO;
                }
            });

            if nodes.is_empty() {
                ui.label("No systems loaded.");
                return;
            }

            let min_x = nodes.iter().map(|n| n.xy.0).fold(f32::INFINITY, f32::min);
            let max_x = nodes.iter().map(|n| n.xy.0).fold(f32::NEG_INFINITY, f32::max);
            let min_y = nodes.iter().map(|n| n.xy.1).fold(f32::INFINITY, f32::min);
            let max_y = nodes.iter().map(|n| n.xy.1).fold(f32::NEG_INFINITY, f32::max);
            let mid_x = (min_x + max_x) * 0.5;
            let mid_y = (min_y + max_y) * 0.5;
            let span_x = (max_x - min_x).max(1.0) * 1.3;
            let span_y = (max_y - min_y).max(1.0) * 1.3;

            let width = ui.available_width().max(510.0);
            let (rect, response) = ui.allocate_exact_size(
                egui::vec2(width, 440.0),
                egui::Sense::click_and_drag(),
            );
            if response.dragged() {
                pan += ui.input(|i| i.pointer.delta());
            }

            let scale = (rect.width() / span_x)
                .min(rect.height() / span_y) * zoom;
            let project = |x: f32, y: f32| {
                egui::pos2(
                    rect.center().x + (x - mid_x) * scale + pan.x,
                    rect.center().y + (y - mid_y) * scale + pan.y,
                )
            };
            let locations: HashMap<String, egui::Pos2> = nodes
                .iter()
                .map(|node| (node.name.to_lowercase(), project(node.xy.0, node.xy.1)))
                .collect();

            let painter = ui.painter_at(rect);
            painter.rect_filled(rect, 4.0, theme::PANEL_BG_SOLID);

            // Only connections backed by actual inter-system gates.
            for (a, b) in &links {
                if let (Some(from), Some(to)) = (
                    locations.get(&a.to_lowercase()),
                    locations.get(&b.to_lowercase()),
                ) {
                    painter.line_segment(
                        [*from, *to],
                        egui::Stroke::new(1.0, theme::PRIMARY_DIM),
                    );
                }
            }

            for node in &nodes {
                let pos = project(node.xy.0, node.xy.1);
                if !rect.contains(pos) {
                    continue;
                }
                let color = node
                    .controlling_faction
                    .as_deref()
                    .map(theme::faction_color)
                    .unwrap_or(theme::TEXT_DIM);
                if node.controlling_faction.is_some() {
                    painter.circle_filled(
                        pos,
                        24.0,
                        egui::Color32::from_rgba_unmultiplied(
                            color.r(), color.g(), color.b(), 32,
                        ),
                    );
                }
                painter.circle_filled(pos, 6.0, color);
                if node.contested {
                    painter.circle_stroke(
                        pos,
                        11.0,
                        egui::Stroke::new(1.5, theme::WARN),
                    );
                }
                if selected.as_deref() == Some(node.name.as_str()) {
                    painter.circle_stroke(
                        pos,
                        15.0,
                        egui::Stroke::new(2.0, theme::PRIMARY),
                    );
                }
                painter.text(
                    egui::pos2(pos.x, pos.y + 12.0),
                    egui::Align2::CENTER_TOP,
                    &node.name,
                    egui::FontId::proportional(11.0),
                    theme::TEXT,
                );
            }

            if response.clicked() {
                if let Some(click) = response.interact_pointer_pos() {
                    if let Some(node) = nodes
                        .iter()
                        .filter(|node| rect.contains(project(node.xy.0, node.xy.1)))
                        .min_by(|a, b| {
                            let da = project(a.xy.0, a.xy.1).distance_sq(click);
                            let db = project(b.xy.0, b.xy.1).distance_sq(click);
                            da.total_cmp(&db)
                        })
                    {
                        if project(node.xy.0, node.xy.1).distance_sq(click) <= 225.0 {
                            selected = Some(node.name.clone());
                        }
                    }
                }
            }

            ui.horizontal_wrapped(|ui| {
                ui.colored_label(theme::TEXT_DIM, "Control:");
                let mut legend: Vec<_> = faction_names.iter().collect();
                legend.sort_by(|a, b| a.1.cmp(b.1));
                for (id, name) in legend {
                    ui.colored_label(theme::faction_color(id), name);
                }
                ui.colored_label(theme::TEXT_DIM, "Neutral / unknown");
                ui.colored_label(theme::WARN, "Ring = contested body");
            });

            if let Some(name) = selected.as_deref() {
                if let Some(node) = nodes.iter().find(|node| node.name == name) {
                    ui.separator();
                    ui.horizontal(|ui| {
                        ui.label(egui::RichText::new(&node.name).strong());
                        let owner = node
                            .controlling_faction
                            .as_ref()
                            .and_then(|id| faction_names.get(id).or(Some(id)))
                            .map(|s| s.as_str())
                            .unwrap_or("Neutral / unknown");
                        ui.label(format!("Control: {owner}"));
                        if node.contested {
                            ui.colored_label(theme::WARN, "Contested");
                        }
                        if ui.button("Focus in 3D").clicked() {
                            focus_req.0 = Some(Vec3::new(
                                node.xy.0 * SCALE_FACTOR,
                                0.0,
                                node.xy.1 * SCALE_FACTOR,
                            ));
                            close_after_focus = true;
                        }
                    });
                }
            }
            ui.label(
                egui::RichText::new(
                    "Prototype: ownership halos, not political borders. Pan by dragging. \
                     Only actual gate links are drawn.",
                )
                .small()
                .color(theme::TEXT_DIM),
            );
        });

    state.open = open && !close_after_focus;
    state.selected = selected;
    state.zoom = zoom;
    state.pan = pan;
}
