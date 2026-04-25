//! Audio — background music + (future) SFX.
//!
//! Bundle 4bk wires the existing `Sci-Fi N Loop.ogg` track set
//! (lifted from the Godot client's `assets/music/`) into Bevy's
//! built-in audio pipeline. One track is picked at startup, played
//! on loop. A `MusicSink` Resource holds the entity / handle so
//! later bundles can layer mute / next-track / volume controls.
//!
//! No SFX yet. When event-driven SFX lands (dock thump, gate-jump
//! whoosh, explosion crack, etc.), it'd hang on the `EventsLog`
//! reader pattern that `event_driven_flashes` already uses in
//! `render::`.

use bevy::prelude::*;
use rand::Rng;

pub struct AudioPlugin;

impl Plugin for AudioPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MusicState>()
            .add_systems(Startup, start_music);
    }
}

/// Tracks the currently-playing music. Held as a Resource so
/// future top-bar / pause-menu controls can `commands.entity(...)`
/// the sink and adjust volume / pause / despawn-and-replace for
/// the next-track button. None on first frame; populated by
/// [`start_music`] in PostStartup.
#[derive(Resource, Default)]
pub struct MusicState {
    pub entity: Option<Entity>,
}

const TRACKS: &[&str] = &[
    "music/Sci-Fi 1 Loop.ogg",
    "music/Sci-Fi 2 Loop.ogg",
    "music/Sci-Fi 3 Loop.ogg",
    "music/Sci-Fi 4 Loop.ogg",
    "music/Sci-Fi 5 Loop.ogg",
    "music/Sci-Fi 6 Loop.ogg",
    "music/Sci-Fi 7 Loop.ogg",
    "music/Sci-Fi 8 Loop.ogg",
];

fn start_music(
    asset_server: Res<AssetServer>,
    mut commands: Commands,
    mut state: ResMut<MusicState>,
) {
    // Pick a random track at boot — same set the Godot client
    // shipped, so play feels familiar across the two clients.
    let mut rng = rand::thread_rng();
    let idx = rng.gen_range(0..TRACKS.len());
    let path = TRACKS[idx];
    info!("client_bevy: starting background music — {}", path);

    let entity = commands
        .spawn(AudioBundle {
            source: asset_server.load(path),
            settings: PlaybackSettings {
                mode: bevy::audio::PlaybackMode::Loop,
                volume: bevy::audio::Volume::new(0.45),
                ..default()
            },
        })
        .id();
    state.entity = Some(entity);
}
