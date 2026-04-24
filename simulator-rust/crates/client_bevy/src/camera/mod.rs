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
    input::mouse::{MouseMotion, MouseWheel},
    prelude::*,
};

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_orbit_camera)
            .add_systems(Update, orbit_camera_input);
    }
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
    /// Default view over the three-system spread. Sol at (0,0), AC at
    /// (200,50), Tau Ceti at (400,-100) → focus on the midpoint of
    /// the spread with enough distance to see all three clusters.
    pub fn initial() -> Self {
        Self {
            focus: Vec3::new(200.0, 0.0, 0.0),
            yaw: 0.0,
            pitch: -0.9, // ~50° down — iso-ish
            distance: 500.0,
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
    commands.spawn((
        Camera3dBundle {
            transform: orbit.transform(),
            ..default()
        },
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

const PITCH_MIN: f32 = -1.45; // ~-83° (almost straight down)
const PITCH_MAX: f32 = -0.1;  // ~-6° (almost horizontal)
const DISTANCE_MIN: f32 = 30.0;
const DISTANCE_MAX: f32 = 2000.0;

#[allow(clippy::too_many_arguments)]
fn orbit_camera_input(
    time: Res<Time>,
    mouse_button: Res<ButtonInput<MouseButton>>,
    keys: Res<ButtonInput<KeyCode>>,
    mut mouse_motion: EventReader<MouseMotion>,
    mut mouse_wheel: EventReader<MouseWheel>,
    mut q: Query<(&mut OrbitCamera, &mut Transform)>,
) {
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

    let mut motion = Vec2::ZERO;
    for ev in mouse_motion.read() {
        motion += ev.delta;
    }

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
    if keys.pressed(KeyCode::KeyW) {
        wasd += fwd;
    }
    if keys.pressed(KeyCode::KeyS) {
        wasd -= fwd;
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

    // --- Scroll zoom ---
    let mut scroll = 0.0;
    for ev in mouse_wheel.read() {
        scroll += ev.y;
    }
    if scroll != 0.0 {
        // Zoom factor scales with current distance so the perceived
        // speed of zooming stays consistent across scales.
        let delta = -scroll * ZOOM_SPEED * (orbit.distance / 200.0);
        orbit.distance = (orbit.distance + delta).clamp(DISTANCE_MIN, DISTANCE_MAX);
        changed = true;
    }

    if changed {
        *xf = orbit.transform();
    }
}
