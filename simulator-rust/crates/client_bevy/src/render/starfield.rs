//! Procedural star sky — port of `client/scripts/world/starfield.gd`'s
//! sky-shader half. Three FBM-grid star layers (bright named stars,
//! neutral mid band, fine dust) rendered on a giant inverted sphere
//! that follows the camera so the sky always reads as infinitely
//! distant. Replaces the 2000-emissive-sphere placeholder.
//!
//! Parallax planes (Godot's second half) deferred — our camera tilts
//! aren't shallow enough that a horizon-band parallax buys much, and
//! the procedural sky alone covers POV / horizontal angles.

use bevy::{
    pbr::{Material, MaterialPlugin, NotShadowCaster, NotShadowReceiver},
    prelude::*,
    render::{
        alpha::AlphaMode,
        render_resource::{AsBindGroup, Face, ShaderRef, ShaderType},
    },
};

pub struct StarfieldPlugin;

impl Plugin for StarfieldPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(MaterialPlugin::<SkyStarsMaterial>::default())
            .add_systems(PostStartup, spawn_sky_shell)
            .add_systems(Update, follow_camera);
    }
}

#[derive(Asset, AsBindGroup, TypePath, Debug, Clone)]
pub struct SkyStarsMaterial {
    #[uniform(0)]
    pub params: SkyParams,
}

#[derive(ShaderType, Debug, Clone, Copy)]
pub struct SkyParams {
    /// 0 = render the sky-stars shader; non-zero = render a
    /// debug "globe direction → RGB" pattern instead so we can
    /// confirm the shell + culling are working before suspecting
    /// the noise math. Toggle via `CLIENT_BEVY_SKY_DEBUG=1`.
    pub debug_mode: u32,
    pub _pad: UVec3,
}

impl Material for SkyStarsMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/sky_stars.wgsl".into()
    }
    /// Render the inside of the shell (cull front faces). Default
    /// Bevy culling drops the back faces of a sphere, which from
    /// inside means we'd see nothing — this flip is the entire
    /// reason the inside is visible.
    fn specialize(
        _pipeline: &bevy::pbr::MaterialPipeline<Self>,
        descriptor: &mut bevy::render::render_resource::RenderPipelineDescriptor,
        _layout: &bevy::render::mesh::MeshVertexBufferLayoutRef,
        _key: bevy::pbr::MaterialPipelineKey<Self>,
    ) -> Result<(), bevy::render::render_resource::SpecializedMeshPipelineError> {
        descriptor.primitive.cull_mode = Some(Face::Front);
        Ok(())
    }
    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Opaque
    }
}

/// Tag for the sky shell so `follow_camera` can find it cheaply.
#[derive(Component)]
struct SkyShell;

/// Shell radius. Big enough that the player can pan/zoom the camera
/// to its `DISTANCE_MAX` clamp and still be inside, with margin so
/// the sky doesn't pop when zoomed out.
const SKY_RADIUS: f32 = 80_000.0;

fn spawn_sky_shell(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<SkyStarsMaterial>>,
) {
    let mesh = meshes.add(Sphere::new(SKY_RADIUS).mesh().ico(4).unwrap());
    let debug_mode = if std::env::var("CLIENT_BEVY_SKY_DEBUG").is_ok() {
        1
    } else {
        0
    };
    let mat = materials.add(SkyStarsMaterial {
        params: SkyParams {
            debug_mode,
            _pad: UVec3::ZERO,
        },
    });
    commands.spawn((
        Mesh3d(mesh),
        MeshMaterial3d::<SkyStarsMaterial>(mat),
        Transform::IDENTITY,
        SkyShell,
        // Belt-and-braces: skybox should never participate in
        // shadow casting/receiving. Bevy default is "everything
        // casts" which would do nothing useful here.
        NotShadowCaster,
        NotShadowReceiver,
        Name::new("SkyStars"),
    ));
}

/// Pin the sky shell to the camera each frame so the camera is
/// always at the centre. With the shell at radius 80k and the
/// camera moving at most ~30k from origin, the sky always reads
/// as infinitely distant rather than a finite sphere we approach.
fn follow_camera(
    mut q_shell: Query<&mut Transform, (With<SkyShell>, Without<Camera>)>,
    q_cam: Query<&Transform, (With<Camera>, Without<SkyShell>)>,
) {
    let Ok(cam) = q_cam.get_single() else {
        return;
    };
    for mut xf in q_shell.iter_mut() {
        xf.translation = cam.translation;
    }
}
