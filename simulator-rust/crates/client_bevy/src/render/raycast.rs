//! Mouse-pick raycasting against ship + facility entities.
//!
//! Two systems read mouse input and convert it to scene picks:
//!   * [`raycast_select`] — left-click → set `SelectedShip` /
//!     `SelectedFacility`. Empty-clicks leave selection unchanged
//!     (matches Godot's feel; an explicit "✕ Clear" widget on the
//!     top bar handles deselect).
//!   * [`raycast_context_menu`] — right-click → set
//!     [`crate::ui::ContextMenuRequest`] which the context-menu egui
//!     overlay reads.
//!
//! Both use a screen-space-aware pick radius (1.5% of camera distance)
//! so the threshold is forgiving when zoomed out without picking
//! through adjacent ships when zoomed in. Picks are rejected when egui
//! wants the pointer (so clicks on panel widgets don't fire a world
//! pick).
//!
//! [`ray_sphere_hit`] is the standard ray-sphere intersection — projects
//! the centre onto the ray, rejects outside the radius, returns depth
//! along the ray for hit ordering.
//!
//! Extracted from `render/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::EguiContexts;

use super::{FacilityEntity, ShipEntity};
use crate::ui::{SelectedFacility, SelectedShip};

/// anything within roughly 10 px at typical FOV — loose enough to be
/// forgiving, tight enough to not pick through adjacent ships.
pub(super) const PICK_RADIUS_FRAC: f32 = 0.015;

/// Left-click raycast against ship + facility render entities, sets
/// the matching Selected* resource on hit. Skips when egui wants the
/// pointer (so clicks on panel widgets don't fire a world pick) and
/// when the click started on nothing (leaves selection unchanged —
/// empty-clicks don't deselect, matching Godot's feel). Uses a
/// screen-space-aware pick radius so the threshold doesn't become
/// unusable when zoomed out.
#[allow(clippy::too_many_arguments)]
pub(super) fn raycast_select(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut selected_ship: ResMut<SelectedShip>,
    mut selected_fac: ResMut<SelectedFacility>,
    mut egui_ctx: EguiContexts,
) {
    if !buttons.just_pressed(MouseButton::Left) {
        return;
    }
    // Skip world picks when the click is on an egui window.
    if egui_ctx.ctx_mut().unwrap().is_pointer_over_area() {
        return;
    }

    let Ok(window) = windows.single() else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    let Ok((camera, cam_xf)) = cameras.single() else {
        return;
    };
    let Ok(ray) = camera.viewport_to_world(cam_xf, cursor) else {
        return;
    };

    // Track best (smallest) depth across all candidates so we pick the
    // nearest thing the ray touches.
    enum Hit {
        Ship(String),
        Facility(String),
    }
    let mut best: Option<(f32, Hit)> = None;

    for (ship, xf) in ships.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Ship(ship.sim_id.clone())));
            }
        }
    }
    for (fac, xf) in facilities.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        // Facilities are visually bigger than ships, so widen the pick
        // radius slightly in kind.
        let r = dist * PICK_RADIUS_FRAC * 1.4;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Facility(fac.sim_id.clone())));
            }
        }
    }

    match best {
        Some((_, Hit::Ship(id))) => {
            selected_ship.0 = Some(id);
            selected_fac.0 = None;
        }
        Some((_, Hit::Facility(id))) => {
            selected_fac.0 = Some(id);
            selected_ship.0 = None;
        }
        None => {
            // Empty click — leave existing selection alone. Matches
            // the Godot feel where clicking starry space doesn't
            // deselect. Users close the details panel to deselect.
        }
    }
}

/// Right-click variant of [`raycast_select`]. Hits a ship or
/// facility under the cursor → writes a `ContextMenuRequest` so the
/// UI can render a popup at the screen position with action items
/// (Inspect / Follow / POV / Destroy). Skips when egui owns the
/// pointer so right-clicks on panels don't surface a world menu.
pub(super) fn raycast_context_menu(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    ships: Query<(&ShipEntity, &Transform)>,
    facilities: Query<(&FacilityEntity, &Transform)>,
    mut menu_req: ResMut<crate::ui::ContextMenuRequest>,
    mut egui_ctx: EguiContexts,
) {
    if !buttons.just_pressed(MouseButton::Right) {
        return;
    }
    if egui_ctx.ctx_mut().unwrap().is_pointer_over_area() {
        return;
    }
    let Ok(window) = windows.single() else { return };
    let Some(cursor) = window.cursor_position() else { return };
    let Ok((camera, cam_xf)) = cameras.single() else { return };
    let Ok(ray) = camera.viewport_to_world(cam_xf, cursor) else {
        return;
    };

    enum Hit {
        Ship(String),
        Facility(String),
    }
    let mut best: Option<(f32, Hit)> = None;
    for (ship, xf) in ships.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Ship(ship.sim_id.clone())));
            }
        }
    }
    for (fac, xf) in facilities.iter() {
        let center = xf.translation;
        let dist = (center - ray.origin).length().max(1.0);
        let r = dist * PICK_RADIUS_FRAC * 1.4;
        if let Some(depth) = ray_sphere_hit(&ray, center, r) {
            if best.as_ref().is_none_or(|(d, _)| depth < *d) {
                best = Some((depth, Hit::Facility(fac.sim_id.clone())));
            }
        }
    }

    let target = match best {
        Some((_, Hit::Ship(id))) => Some(crate::ui::ContextMenuTarget::Ship(id)),
        Some((_, Hit::Facility(id))) => Some(crate::ui::ContextMenuTarget::Facility(id)),
        None => return, // empty right-click leaves any open menu alone
    };

    *menu_req = crate::ui::ContextMenuRequest {
        target,
        screen_pos: Vec2::new(cursor.x, cursor.y),
    };
}
/// Standard ray-sphere hit test. Returns the depth along the ray if
/// the ray enters the sphere, None otherwise. We project the sphere
/// centre onto the ray, then reject when the perpendicular distance
/// exceeds the radius. "Behind camera" filtered via the early t<0.
pub(super) fn ray_sphere_hit(ray: &Ray3d, center: Vec3, radius: f32) -> Option<f32> {
    let dir = ray.direction.as_vec3();
    let to_center = center - ray.origin;
    let t = to_center.dot(dir);
    if t < 0.0 {
        return None;
    }
    let closest = ray.origin + dir * t;
    let perp2 = (center - closest).length_squared();
    if perp2 <= radius * radius {
        Some(t)
    } else {
        None
    }
}
