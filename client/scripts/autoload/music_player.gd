extends Node

## Background music shuffler. Scans `MUSIC_DIR` at startup, plays a
## random track, then queues the next random track when the current one
## finishes. Tracks don't repeat back-to-back (unless there's only one).
##
## Tracks are shipped as .ogg files — Godot auto-imports them. This
## autoload finds them via `DirAccess` so you can drop new .ogg files in
## the folder and they'll be picked up on next run without code changes.
##
## The .ogg files may have been imported with loop=true; we force
## loop=false per-play so the `finished` signal fires and the shuffler
## can move on instead of the same track playing forever.

const MUSIC_DIR := "res://assets/music"

## Hardcoded fallback list. Required because:
##   1. Godot's exporter only tracks resources through `preload()`,
##      scene `ext_resource` refs, or `@export` fields. Our runtime
##      `load(_tracks[idx])` uses a string computed from a DirAccess
##      scan, so the exporter can't statically prove the .ogg files
##      are needed and may strip them.
##   2. `DirAccess.list_dir_begin()` in exported builds doesn't
##      reliably enumerate source audio files — they get imported
##      to .oggvorbisstr and the packed filesystem may not surface
##      the original `.ogg` names.
##
## Using `preload()` here tells the exporter "these resources are
## definitely needed" AND gives us a resource that works regardless
## of how the packaged filesystem is laid out. Dev mode (editor)
## also runs a dir scan below so new .ogg files auto-appear without
## editing this list.
const KNOWN_TRACKS: Array[AudioStream] = [
  preload("res://assets/music/Sci-Fi 1 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 2 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 3 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 4 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 5 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 6 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 7 Loop.ogg"),
  preload("res://assets/music/Sci-Fi 8 Loop.ogg"),
]

@export var auto_start: bool = true

# Each entry is either a String path (for files found via DirAccess
# in editor) or an AudioStream (preloaded). _play_random handles both.
var _tracks: Array = []
var _player: AudioStreamPlayer
var _last_idx: int = -1


func _ready() -> void:
  _player = AudioStreamPlayer.new()
  # Route to the Music bus — SettingsManager owns per-bus volume, so
  # we don't set volume_db here. Bus is created by SettingsManager's
  # _ready which runs first (it's earlier in project.godot's autoload
  # order). If the bus somehow doesn't exist, Godot falls back to
  # Master which is an acceptable degraded mode.
  _player.bus = &"Music"
  _player.finished.connect(_on_track_finished)
  add_child(_player)

  _scan_tracks()
  if auto_start and _tracks.size() > 0:
    _play_random()
  elif _tracks.size() == 0:
    push_warning(
      "MusicPlayer: no .ogg tracks found under %s" % MUSIC_DIR
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_volume(db: float) -> void:
  ## Kept for API parity — routes to the Music bus directly. Prefer
  ## SettingsManager.set_music_volume() for anything UI-driven so the
  ## value persists to settings.cfg.
  var idx := AudioServer.get_bus_index(&"Music")
  if idx >= 0:
    AudioServer.set_bus_volume_db(idx, db)


func stop() -> void:
  if _player:
    _player.stop()


func skip() -> void:
  ## Jump straight to a new random track, ignoring the current one.
  _play_random()


func is_playing() -> bool:
  return _player != null and _player.playing


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _scan_tracks() -> void:
  # Editor path: scan the folder so dropping a new .ogg in gets picked
  # up without touching this file. Skip in exported builds — the
  # packed filesystem doesn't surface .ogg names reliably, and we
  # have the preloaded KNOWN_TRACKS list anyway.
  if OS.has_feature("editor"):
    var dir := DirAccess.open(MUSIC_DIR)
    if dir:
      dir.list_dir_begin()
      var f := dir.get_next()
      while f != "":
        if not dir.current_is_dir() and f.to_lower().ends_with(".ogg"):
          _tracks.append(MUSIC_DIR.path_join(f))
        f = dir.get_next()
      dir.list_dir_end()
      _tracks.sort()

  # Always append the preloaded known tracks so exported builds are
  # guaranteed to have a list. In editor mode the scan above may
  # already have paths — we'll dedupe below by preferring preloaded
  # resources (they skip the runtime load).
  var scanned_names: Dictionary = {}
  for t in _tracks:
    if t is String:
      scanned_names[(t as String).get_file()] = true

  for stream in KNOWN_TRACKS:
    if stream == null:
      continue
    var src_path: String = stream.resource_path
    # Skip if we already picked up this file via scan — the preloaded
    # version replaces the string path so we load once, not twice.
    if scanned_names.has(src_path.get_file()):
      # Swap the string entry for the preloaded AudioStream so load
      # happens zero times at play time.
      for i in range(_tracks.size()):
        if _tracks[i] is String \
            and (_tracks[i] as String).get_file() == src_path.get_file():
          _tracks[i] = stream
          break
    else:
      _tracks.append(stream)


func _play_random() -> void:
  if _tracks.size() == 0:
    return
  var idx: int = randi() % _tracks.size()
  if _tracks.size() > 1 and idx == _last_idx:
    # Nudge forward so we never play the same track twice in a row.
    idx = (idx + 1) % _tracks.size()
  _last_idx = idx

  var entry: Variant = _tracks[idx]
  var stream: AudioStream
  if entry is AudioStream:
    stream = entry
  elif entry is String:
    stream = load(entry) as AudioStream
  else:
    push_warning("MusicPlayer: unknown track entry type")
    return
  if stream == null:
    push_warning("MusicPlayer: failed to load track %s" % entry)
    return
  # Force loop off so the `finished` signal fires. `.set()` silently
  # no-ops if the concrete stream type doesn't expose `loop`.
  stream.set("loop", false)
  _player.stream = stream
  _player.play()


func _on_track_finished() -> void:
  _play_random()
