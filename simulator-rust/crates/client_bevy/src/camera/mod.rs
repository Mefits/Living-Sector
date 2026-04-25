//! Orbit + pan + zoom camera for the galactic-overview view.
//!
//! Bevy doesn't ship a built-in orbit-camera plugin in 0.14, so we
//! implement a small one tuned to this game's feel:
//!
//! - **Middle-click drag** or **left-click drag**: orbit around the
//!   look-at point (pitch + yaw)
//! - **Right-click drag** or **WASD**: pan the look-at point across
//!   the galactic plane
//! - **Mouse scroll**: zoom (distance from look-at point)
//!
//! The camera Entity stores its own state (yaw / pitch / distance /
//! focus) so we're not reading Transform and back-computing angles.

use bevy::{
    core_pipeline::bloom::BloomSettings,
    input::{
        gestures::PinchGesture,
        mouse::{MouseMotion, MouseWheel},
    },
    prelude::*,
};
use bevy_egui::EguiContexts;

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CameraFocusRequest>()
            .init_resource::<CameraResetRequest>()
            .init_resource::<CameraFollow>()
            .add_systems(Startup, spawn_orbit_camera)
            .add_systems(
                Update,
                (orbit_camera_input, apply_focus_request, apply_reset_request),
            );
    }
}

/// One-shot request to snap the camera's focus point to a world-space
/// position. Set by UI button handlers (ship/facility details panels);
/// consumed by [`apply_focus_request`] the same frame. Kept as a
/// Resource rather than an Event so systems can read/mutate it without
/// an `EventWriter/EventReader` pair — the semantics are "latest wins,
/// consumed on apply", which an Option models more directly.
#[derive(Resource, Default)]
pub struct CameraFocusRequest(pub Option<Vec3>);

/// One-shot request to restore the camera to its initial pose —
/// same focus / yaw / pitch / distance as a fresh boot. Set by the
/// top-bar "Reset view" button; consumed by [`apply_reset_request`].
/// Separate from `CameraFocusRequest` because a reset clobbers yaw /
/// pitch / distance too, not just the focus point.
#[derive(Resource, Default)]
pub struct CameraResetRequest(pub bool);

/// Continuous camera-follow target. Unlike `CameraFocusRequest`
/// (one-shot snap), this is consumed every frame by a render-side
/// system that rewrites `OrbitCamera.focus` from the entity's live
/// transform. Cleared automatically when the user pans manually
/// (WASD / right-drag) so muscle memory takes precedence over a
/// stale follow lock. Set by the right-click context menu's
/// Follow / POV items.
#[derive(Resource, Default)]
pub struct CameraFollow {
    pub target: Option<CameraFollowTarget>,
    /// When set, the apply system snaps `distance` to this value
    /// once and clears it. POV uses a small distance for an "above
    /// the shoulder" feel; Follow leaves it alone.
    pub snap_distance: Option<f32>,
}

#[derive(Clone, Debug)]
pub enum CameraFollowTarget {
    Ship(String),
    Facility(String),
}

/// Orbit camera state. Attached to the Camera3d entity so the
/// control system can read/mutate it alongside the Transform.
#[derive(Component)]
pub struct OrbitCamera {
    /// World-space point the camera pivots around / pans across.
    pub focus: Vec3,
    /// Angular orbit, radians. Yaw around Y, pitch from horizontal.
    pub yaw: f32,
    pub pitch: f32,
    /// Distance from focus to eye.
    pub distance: f32,
}

impl OrbitCamera {
    /// Default view: focus on Sol at the universe origin so the
    /// boot screen shows inner-system bodies + their stations,
    /// not empty space. Sol's outer bodies (Saturn, Kuiper) sit
    /// out near 5000 wu with `SCALE_FACTOR = 60`, but Earth and
    /// the inner planets are within ~1500 wu of origin — so
    /// distance ~3500 lands a comfortable iso view of the inner
    /// system. Other systems spread to 4800 wu+ on +X; user
    /// zooms out + pans to see them.
    pub fn initial() -> Self {
        Self {
            focus: Vec3::new(0.0, 0.0, 0.0),
            yaw: 0.0,
            pitch: -0.9, // ~50° down — iso-ish
            distance: 3500.0,
        }
    }

    /// Recompute the eye position + looking direction for this
    /// orbit state. Called whenever input moves us.
    fn transform(&self) -> Transform {
        let (sy, cy) = self.yaw.sin_cos();
        let (sp, cp) = self.pitch.sin_cos();
        // Spherical coords around focus. pitch = 0 is horizontal,
        // negative pitch looks down. Standard convention.
        let offset = Vec3::new(
            self.distance * cp * sy,
            -self.distance * sp,
            self.distance * cp * cy,
        );
        let eye = self.focus + offset;
        Transform::from_translation(eye).looking_at(self.focus, Vec3::Y)
    }
}

fn spawn_orbit_camera(mut commands: Commands) {
    let orbit = OrbitCamera::initial();
    // Stretch the far clip plane well beyond the star shell
    // (STAR_FIELD_RADIUS = 4000) + the nebula shell
    // (NEBULA_FIELD_RADIUS = 9000) so backdrop elements actually
    // render. Default Bevy far is 1000, which culls the whole
    // backdrop at galactic zoom.
    let projection = Projection::Perspective(PerspectiveProjection {
        near: 0.1,
        far: 120_000.0,
        ..default()
    });
    // HDR + bloom so emissive ship + body + nebula materials
    // actually bloom on-screen. Without these, emissive just adds
    // to base colour — sub-pixel ships are invisible. With HDR
    // post-process, a half-pixel spark paints several pixels of
    // colour — ships become visible at galactic zoom.
    commands.spawn((
        Camera3dBundle {
            camera: Camera {
                hdr: true,
                ..default()
            },
            transform: orbit.transform(),
            projection,
            ..default()
        },
        BloomSettings::NATURAL,
        orbit,
        Name::new("OrbitCamera"),
    ));
}

/// Camera-feel constants — kept inline rather than Resources since
/// they're not runtime-tunable (yet).
const ORBIT_SPEED: f32 = 0.004; // radians per pixel of mouse motion
const PAN_SPEED: f32 = 0.5;     // world units per pixel of mouse motion (scales w/ distance)
const WASD_SPEED: f32 = 200.0;  // world units per second at WASD
const ZOOM_SPEED: f32 = 20.0;   // world units per scroll line
/// Per-key zoom step when held — `=`/`+` zoom in, `-`/`_` zoom out.
/// Tuned so a held key noticeably moves the camera without feeling
/// twitchy. Trackpad users without scroll-up/down rely on this.
const KEY_ZOOM_STEP: f32 = 600.0; // wu per second
/// Pinch-gesture multiplier. macOS PinchGesture deltas come in
/// small fractional values per event (~0.01 per gentle pinch frame);
/// scale them up so a normal pinch covers a useful zoom range.
const PINCH_ZOOM_FACTOR: f32 = 600.0;

const PITCH_MIN: f32 = -1.45; // ~-83° (almost straight down)
const PITCH_MAX: f32 = -0.1;  // ~-6° (almost horizontal)
const DISTANCE_MIN: f32 = 8.0;
const DISTANCE_MAX: f32 = 30_000.0;

#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_arguments)]
fn orbit_camera_input(
    time: Res<Time>,
    mouse_button: Res<ButtonInput<MouseButton>>,
    keys: Res<ButtonInput<KeyCode>>,
    mut mouse_motion: EventReader<MouseMotion>,
    mut mouse_wheel: EventReader<MouseWheel>,
    mut pinch: EventReader<PinchGesture>,
    mut egui_ctx: EguiContexts,
    mut q: Query<(&mut OrbitCamera, &mut Transform)>,
    mut follow: ResMut<CameraFollow>,
) {
    // Drain the input event readers regardless of whether the camera
    // accepts them, so a click that originated on a panel doesn't
    // bleed into the next frame's camera state. `read()` consumes the
    // events; `pressed()` queries on `Res<ButtonInput>` are independent
    // of these readers and stay reliable.
    let mut motion = Vec2::ZERO;
    for ev in mouse_motion.read() {
        motion += ev.delta;
    }
    let mut scroll = 0.0;
    for ev in mouse_wheel.read() {
        scroll += ev.y;
    }
    let mut pinch_delta = 0.0;
    for ev in pinch.read() {
        pinch_delta += ev.0;
    }

    // egui owns input when the cursor is over a panel/window (drag
    // headers, scroll wheel inside a list, button clicks). Bail
    // before we convert any of that into camera motion. The
    // `wants_*` queries cover keyboard focus too — typing in a
    // filter box won't trigger WASD pan.
    let egui_owns = {
        let ctx = egui_ctx.ctx_mut();
        ctx.wants_pointer_input()
            || ctx.is_pointer_over_area()
            || ctx.wants_keyboard_input()
    };
    if egui_owns {
        return;
    }

    let Ok((mut orbit, mut xf)) = q.get_single_mut() else {
        return;
    };

    let dt = time.delta_seconds();
    let mut changed = false;

    // --- Mouse orbit (middle or left drag) ---
    let orbiting = mouse_button.pressed(MouseButton::Middle)
        || (mouse_button.pressed(MouseButton::Left) && !keys.pressed(KeyCode::ShiftLeft));
    let panning = mouse_button.pressed(MouseButton::Right)
        || (mouse_button.pressed(MouseButton::Left) && keys.pressed(KeyCode::ShiftLeft));

    if orbiting && motion != Vec2::ZERO {
        orbit.yaw -= motion.x * ORBIT_SPEED;
        orbit.pitch = (orbit.pitch + motion.y * ORBIT_SPEED).clamp(PITCH_MIN, PITCH_MAX);
        changed = true;
    }

    // --- Mouse-drag pan (right or shift+left) ---
    if panning && motion != Vec2::ZERO {
        // Pan scales with zoom distance so you don't have to flick
        // the mouse across the room when zoomed out.
        let scale = PAN_SPEED * (orbit.distance / 500.0);
        let (sy, cy) = orbit.yaw.sin_cos();
        let right = Vec3::new(cy, 0.0, -sy);
        let fwd = Vec3::new(sy, 0.0, cy); // flat-projected forward
        orbit.focus -= right * motion.x * scale;
        orbit.focus -= fwd * motion.y * scale;
        changed = true;
    }

    // --- WASD pan (relative to camera yaw) ---
    let (sy, cy) = orbit.yaw.sin_cos();
    let right = Vec3::new(cy, 0.0, -sy);
    let fwd = Vec3::new(sy, 0.0, cy);
    let mut wasd = Vec3::ZERO;
    // W/S map to "screen-up" / "screen-down" panning, i.e. the camera
    // focus moves opposite the eye-to-target direction. With our
    // top-down iso tilt that means W subtracts fwd (focus shifts
    // toward the camera, world content scrolls down) and S adds it.
    // The intuitive mapping for a strategy-style top-down: W feels
    // like "scroll the map up" / "look at what's above", which
    // matches how the user expects WASD to behave.
    if keys.pressed(KeyCode::KeyW) {
        wasd -= fwd;
    }
    if keys.pressed(KeyCode::KeyS) {
        wasd += fwd;
    }
    if keys.pressed(KeyCode::KeyD) {
        wasd += right;
    }
    if keys.pressed(KeyCode::KeyA) {
        wasd -= right;
    }
    if wasd != Vec3::ZERO {
        let scale = WASD_SPEED * dt * (orbit.distance / 500.0);
        orbit.focus += wasd.normalize() * scale;
        changed = true;
    }

    // Manual pan (wasd OR right-drag) breaks any active follow lock —
    // user intent wins over a stale right-click follow.
    if (wasd != Vec3::ZERO || (panning && motion != Vec2::ZERO))
        && follow.target.is_some()
    {
        follow.target = None;
        follow.snap_distance = None;
    }

    // --- Scroll zoom (mouse wheel + trackpad two-finger scroll) ---
    if scroll != 0.0 {
        // Zoom factor scales with current distance so the perceived
        // speed of zooming stays consistent across scales.
        let delta = -scroll * ZOOM_SPEED * (orbit.distance / 200.0);
        orbit.distance = (orbit.distance + delta).clamp(DISTANCE_MIN, DISTANCE_MAX);
        changed = true;
    }

    // --- Pinch-gesture zoom (macOS trackpad). Bevy 0.14's
    // PinchGesture surfaces magnification deltas (positive = pinch
    // out / zoom in, negative = pinch in / zoom out).
    if pinch_delta != 0.0 {
        let delta = -pinch_delta * PINCH_ZOOM_FACTOR * (orbit.distance / 500.0);
        orbit.distance = (orbit.distance + delta).clamp(DISTANCE_MIN, DISTANCE_MAX);
        changed = true;
    }

    // --- Keyboard zoom (`=`/`+` in, `-`/`_` out). Continuous while
    // held — for trackpad users without scroll-wheel zoom or for
    // precise framing. Both Equal and NumpadAdd map to zoom-in.
    let mut key_zoom = 0.0;
    if keys.pressed(KeyCode::Equal) || keys.pressed(KeyCode::NumpadAdd) {
        key_zoom -= 1.0;
    }
    if keys.pressed(KeyCode::Minus) || keys.pressed(KeyCode::NumpadSubtract) {
        key_zoom += 1.0;
    }
    if key_zoom != 0.0 {
        let delta = key_zoom * KEY_ZOOM_STEP * dt * (orbit.distance / 500.0);
        orbit.distance = (orbit.distance + delta).clamp(DISTANCE_MIN, DISTANCE_MAX);
        changed = true;
    }

    if changed {
        *xf = orbit.transform();
    }
}

/// Consume any pending [`CameraFocusRequest`] by snapping the orbit
/// camera's focus to the requested point. Single snap — we don't keep
/// tracking the target — so the user's manual pan/orbit/zoom input
/// retakes control the moment they move the mouse.
fn apply_focus_request(
    mut req: ResMut<CameraFocusRequest>,
    mut q: Query<(&mut OrbitCamera, &mut Transform)>,
) {
    let Some(target) = req.0.take() else {
        return;
    };
    let Ok((mut orbit, mut xf)) = q.get_single_mut() else {
        return;
    };
    orbit.focus = target;
    *xf = orbit.transform();
}

/// Consume any pending [`CameraResetRequest`] by rewriting the
/// OrbitCamera to its fresh-boot pose. Use when the user has
/// panned / zoomed into nowhere and can't find their way back.
fn apply_reset_request(
    mut req: ResMut<CameraResetRequest>,
    mut q: Query<(&mut OrbitCamera, &mut Transform)>,
) {
    if !req.0 {
        return;
    }
    req.0 = false;
    let Ok((mut orbit, mut xf)) = q.get_single_mut() else {
        return;
    };
    *orbit = OrbitCamera::initial();
    *xf = orbit.transform();
}
