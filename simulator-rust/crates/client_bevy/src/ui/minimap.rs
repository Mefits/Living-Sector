//! Minimap panel.
//!
//! Top-down overview of the galaxy: bodies as medium PRIMARY-tinted
//! dots, ships as tiny TEXT_DIM dots, a WARN-coloured crosshair at
//! the camera focus. Bounds auto-fit to the body cluster each frame
//! with a 10% margin so systems at the edge aren't clipped.
//!
//! Click anywhere on the minimap to recenter the orbit camera on
//! that universe position — cheap navigation across systems.
//!
//! State: [`MinimapState`] (just an `open` flag — the layout is
//! fully derived from sim state each frame, no persistence needed).
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::camera::{CameraFocusRequest, OrbitCamera};
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[derive(Resource, Default)]
pub(super) struct MinimapState {
    pub open: bool,
}

pub(super) fn minimap_panel(
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
