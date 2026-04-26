//! Right-click world context menu.
//!
//! Renders an egui popup at the right-click cursor with four items:
//!   * **Inspect** — selects the entity (opens its details panel).
//!   * **Follow** — locks the orbit camera's focus to the entity each
//!     frame; user pan clears the lock.
//!   * **POV** — true third-person chase mode; orbit yaw / pitch /
//!     distance are overridden from the ship's heading each frame.
//!   * **Destroy** — fires `DeleteShipRequest` / `DeleteFacilityRequest`.
//!     No confirmation — admin tool, embedded client, undo == restart.
//!
//! State: [`ContextMenuRequest`] — `target = None` means hidden.
//! `screen_pos` anchors the popup. The request is set by
//! `render::raycast_context_menu` on right-click and read here.
//!
//! Spawn-frame race: egui's `is_pointer_over_area()` returns false on
//! the frame an Area is first registered. Without the `just_opened`
//! guard the very right-click that spawned the menu would fail the
//! click-outside check on the same frame and dismiss it. The
//! `prev_target` Local tracks frame-to-frame target identity so we
//! skip the dismiss check exactly once when the menu opens or
//! retargets.
//!
//! Click-outside dismiss watches left-click only — right-click is
//! owned by `raycast_context_menu` (it either retargets to a fresh
//! entity or leaves empty space as a no-op). Listening for right
//! here would race with that path.
//!
//! Extracted from `ui/mod.rs` in the Phase-21 god-module split.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use super::facility::SelectedFacility;
use super::ship_list::SelectedShip;
use super::theme;

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

#[allow(clippy::too_many_arguments)]
pub(super) fn context_menu(
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

    let ctx_ref = ctx.ctx_mut().unwrap();
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
