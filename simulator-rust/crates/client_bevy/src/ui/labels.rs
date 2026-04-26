//! Screen-space label overlays for bodies, ships, facilities, and
//! construction sites.
//!
//! Each panel projects the relevant entities' world positions to
//! screen-space using the active camera and paints text labels in a
//! transparent, non-interactive `egui::Area` so labels never eat
//! clicks or block tooltips. All four overlays share
//! [`BodyLabelsState`] (the top-bar "Labels" toggle gates them all).
//!
//! Zoom-gating tiers (orbit camera distance, world units):
//!
//! | Tier | Max dist | Reason |
//! |---|---|---|
//! | Body | always-on | ~30 bodies, orientation anchor |
//! | Facility | 500 | only matters when zoomed into a system |
//! | Construction | 500 | progress-% only useful close-in |
//! | Ship | 75 | tightest — density would carpet the screen otherwise |
//!
//! [`label_min_y`] clips labels so they don't overlap the always-on
//! top bar — egui's layer ordering doesn't actually push
//! Background-ordered Areas below TopBottomPanels in practice.
//! Calling systems must run `.after(top_bar)` so
//! `available_rect().top()` reflects the post-top-bar Y.
//!
//! Ship labels read positions from each ship's Bevy
//! `GlobalTransform` (already lerped by `sync_positions` between
//! ticks), not the tick-quantized `ShipPosition` in hecs — labels
//! glide with the meshes instead of snapping on tick boundaries.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::theme;
use crate::camera::OrbitCamera;
use crate::render::SCALE_FACTOR;
use crate::sim::Sim;

#[derive(Resource)]
pub(super) struct BodyLabelsState {
    pub show: bool,
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

pub(super) fn body_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
) {
    use sim_core::agents::celestial_body::{BodyIdentity, BodyOrbit};

    if !state.show {
        return;
    }

    let Ok((camera, cam_xf)) = camera_q.single() else {
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
    let ctx = ctx.ctx_mut().unwrap();
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
                let Ok(screen) = camera.world_to_viewport(cam_xf, pos) else {
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
pub(super) fn construction_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform, &OrbitCamera), With<Camera3d>>,
) {
    use sim_core::agents::construction::ConstructionSite;
    if !state.show {
        return;
    }
    let Ok((camera, cam_xf, orbit)) = camera_q.single() else {
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

    let ctx = ctx.ctx_mut().unwrap();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("construction_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, prog, pos) in entries {
                let Ok(screen) = camera.world_to_viewport(cam_xf, pos) else {
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
pub(super) fn facility_labels_panel(
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
    let Ok((camera, cam_xf, orbit)) = camera_q.single() else {
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

    let ctx = ctx.ctx_mut().unwrap();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("facility_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                let Ok(screen) = camera.world_to_viewport(cam_xf, pos) else {
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
pub(super) fn ship_labels_panel(
    mut ctx: EguiContexts,
    state: Res<BodyLabelsState>,
    sim: Res<Sim>,
    camera_q: Query<(&Camera, &GlobalTransform, &OrbitCamera), With<Camera3d>>,
    ships_q: Query<(&crate::render::ShipEntity, &GlobalTransform)>,
) {
    use sim_core::agents::ship::ShipIdentity;
    if !state.show {
        return;
    }
    let Ok((camera, cam_xf, orbit)) = camera_q.single() else {
        return;
    };
    if orbit.distance > SHIP_LABEL_MAX_DIST {
        return;
    }

    // Read positions from each Bevy ship entity's `GlobalTransform`
    // — that's already lerped between sim ticks by `sync_positions`
    // (render/mod.rs) using `Time::<Fixed>::overstep_fraction()`.
    // Querying `ShipPosition` from the hecs world here would yield
    // the tick-quantized authoritative position, so labels would
    // snap on every tick boundary while the ship meshes glide. The
    // hecs world is consulted only for the display name.
    let names: std::collections::HashMap<String, String> = sim
        .store
        .world
        .query::<&ShipIdentity>()
        .iter()
        .map(|(_e, id)| (id.id.clone(), id.name.clone()))
        .collect();

    let entries: Vec<(String, Vec3)> = ships_q
        .iter()
        .filter_map(|(ship, xf)| {
            names
                .get(&ship.sim_id)
                .cloned()
                .map(|name| (name, xf.translation()))
        })
        .collect();

    let ctx = ctx.ctx_mut().unwrap();
    let min_y = label_min_y(ctx);
    egui::Area::new(egui::Id::new("ship_labels_area"))
        .movable(false)
        .interactable(false)
        .order(egui::Order::Background)
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .show(ctx, |ui| {
            let painter = ui.painter();
            for (name, pos) in entries {
                let Ok(screen) = camera.world_to_viewport(cam_xf, pos) else {
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
