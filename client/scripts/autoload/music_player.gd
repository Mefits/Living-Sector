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

@export var music_volume_db: float = -14.0
@export var auto_start: bool = true

var _tracks: Array[String] = []
var _player: AudioStreamPlayer
var _last_idx: int = -1


func _ready() -> void:
  _player = AudioStreamPlayer.new()
  _player.volume_db = music_volume_db
  _player.bus = "Master"
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
  music_volume_db = db
  if _player:
    _player.volume_db = db


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
  var dir := DirAccess.open(MUSIC_DIR)
  if not dir:
    push_warning("MusicPlayer: can't open dir %s" % MUSIC_DIR)
    return
  dir.list_dir_begin()
  var f := dir.get_next()
  while f != "":
    if not dir.current_is_dir() and f.to_lower().ends_with(".ogg"):
      _tracks.append(MUSIC_DIR.path_join(f))
    f = dir.get_next()
  dir.list_dir_end()
  # Stable order so the "no repeat" heuristic below is meaningful.
  _tracks.sort()


func _play_random() -> void:
  if _tracks.size() == 0:
    return
  var idx: int = randi() % _tracks.size()
  if _tracks.size() > 1 and idx == _last_idx:
    # Nudge forward so we never play the same track twice in a row.
    idx = (idx + 1) % _tracks.size()
  _last_idx = idx

  var stream := load(_tracks[idx]) as AudioStream
  if stream == null:
    push_warning("MusicPlayer: failed to load %s" % _tracks[idx])
    return
  # Force loop off so the `finished` signal fires. `.set()` silently
  # no-ops if the concrete stream type doesn't expose `loop`.
  stream.set("loop", false)
  _player.stream = stream
  _player.play()


func _on_track_finished() -> void:
  _play_random()
