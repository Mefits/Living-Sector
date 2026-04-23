extends Node

## Persists user-facing settings + wires audio buses so volume sliders
## are a single dial per category instead of walking every player.
##
## Layout:
##   Master ←── Music  (everything MusicPlayer plays)
##          └── SFX    (everything ProceduralAudio plays)
##
## Buses are added programmatically at _ready so we don't need a
## default_bus_layout.tres checked in. MusicPlayer and ProceduralAudio
## route their players to the named buses; this script is the single
## owner of per-bus volume.
##
## Persistence: user://settings.cfg via Godot's ConfigFile. Written on
## every setter call — ConfigFile is cheap and saves are tiny.
##
## UI contract: sliders are linear 0.0..1.0. `linear_to_db()` converts
## for the audio engine. 0.0 slams the bus to a silence floor (-80 dB)
## because `linear_to_db(0)` is -inf which some audio drivers hate.

signal music_volume_changed(linear: float)
signal sfx_volume_changed(linear: float)

const SETTINGS_PATH := "user://settings.cfg"

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

const SILENCE_DB := -80.0

# Defaults chosen so a fresh install has audible-but-not-jarring volumes.
# 0.6 linear ≈ -4.4 dB — background-friendly.
const DEFAULT_MUSIC_LINEAR := 0.35
const DEFAULT_SFX_LINEAR := 0.60

var music_volume_linear: float = DEFAULT_MUSIC_LINEAR
var sfx_volume_linear: float = DEFAULT_SFX_LINEAR


func _ready() -> void:
  _ensure_buses()
  _load()
  _apply_music()
  _apply_sfx()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_music_volume(linear: float) -> void:
  music_volume_linear = clampf(linear, 0.0, 1.0)
  _apply_music()
  _save()
  music_volume_changed.emit(music_volume_linear)


func set_sfx_volume(linear: float) -> void:
  sfx_volume_linear = clampf(linear, 0.0, 1.0)
  _apply_sfx()
  _save()
  sfx_volume_changed.emit(sfx_volume_linear)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _ensure_buses() -> void:
  ## Add Music / SFX buses if they aren't already there, each routed
  ## to Master. Runs before MusicPlayer / ProceduralAudio _ready so
  ## their players can bind to these bus names on first use —
  ## SettingsManager is registered earliest in project.godot's
  ## autoload list to make that order guaranteed.
  if AudioServer.get_bus_index(MUSIC_BUS) < 0:
    AudioServer.add_bus()
    var idx := AudioServer.get_bus_count() - 1
    AudioServer.set_bus_name(idx, MUSIC_BUS)
    AudioServer.set_bus_send(idx, "Master")
  if AudioServer.get_bus_index(SFX_BUS) < 0:
    AudioServer.add_bus()
    var idx := AudioServer.get_bus_count() - 1
    AudioServer.set_bus_name(idx, SFX_BUS)
    AudioServer.set_bus_send(idx, "Master")


func _apply_music() -> void:
  var idx := AudioServer.get_bus_index(MUSIC_BUS)
  if idx < 0:
    return
  AudioServer.set_bus_volume_db(idx, _linear_to_bus_db(music_volume_linear))


func _apply_sfx() -> void:
  var idx := AudioServer.get_bus_index(SFX_BUS)
  if idx < 0:
    return
  AudioServer.set_bus_volume_db(idx, _linear_to_bus_db(sfx_volume_linear))


func _linear_to_bus_db(linear: float) -> float:
  # 0.0 → silence floor (-inf makes some drivers warn). Everything
  # else uses the standard log conversion.
  if linear <= 0.0001:
    return SILENCE_DB
  return linear_to_db(linear)


func _load() -> void:
  var cfg := ConfigFile.new()
  var err := cfg.load(SETTINGS_PATH)
  if err != OK:
    # Fresh install or corrupt file — keep defaults, save on first
    # slider change.
    return
  music_volume_linear = clampf(
    cfg.get_value("audio", "music_linear", DEFAULT_MUSIC_LINEAR),
    0.0, 1.0
  )
  sfx_volume_linear = clampf(
    cfg.get_value("audio", "sfx_linear", DEFAULT_SFX_LINEAR),
    0.0, 1.0
  )


func _save() -> void:
  var cfg := ConfigFile.new()
  cfg.set_value("audio", "music_linear", music_volume_linear)
  cfg.set_value("audio", "sfx_linear", sfx_volume_linear)
  var err := cfg.save(SETTINGS_PATH)
  if err != OK:
    push_warning(
      "[SettingsManager] save failed (%d) at %s"
      % [err, SETTINGS_PATH]
    )
