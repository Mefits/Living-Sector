extends Node

## Procedural audio. Every sound is synthesised at runtime into an
## AudioStreamWAV — no audio files shipped. Registered as the
## `ProceduralAudio` autoload so calls read like
##   `ProceduralAudio.play_explosion(pos, size_hint)`.
##
## Two dispatch styles:
##   - 3D: round-robin pool of AudioStreamPlayer3D, spatialised around
##     the camera. Older voices get cut by the pool wrap rather than
##     mixed in endlessly.
##   - 2D: a single shared AudioStreamPlayer for UI / non-positional
##     cues. One voice — a new UI blip interrupts the old one.
##
## All synthesis is pure GDScript math into a PCM16 PackedByteArray.
## At 22.05 kHz mono a ~1-second explosion is ~44 KB; generation runs
## in < 10ms per sound on our target hardware, fine for one-shots.

const SAMPLE_RATE := 22050
const POOL_SIZE_3D := 16
# Small UI pool so rapid clicks can overlap. Single-player cut each
# new click off before the pitch change had time to register, which
# is why pentatonic chain changes sounded "all the same".
const POOL_SIZE_UI := 6

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_idx: int = 0
var _pool_ui: Array[AudioStreamPlayer] = []
var _pool_ui_idx: int = 0


func _ready() -> void:
  # All SFX routes through the "SFX" bus so SettingsManager's slider
  # is a single dial. Bus is created by SettingsManager before this
  # autoload's _ready runs.
  for i in range(POOL_SIZE_3D):
    var p := AudioStreamPlayer3D.new()
    # Tuning: units are world-space. unit_size = "distance at which
    # sound plays at 0 dB"; max_distance is the fall-off ceiling. Our
    # camera typically sits 10–80 units out, so a unit_size of 8 keeps
    # nearby explosions prominent without deafening the player on
    # close zooms.
    p.unit_size = 8.0
    p.max_distance = 200.0
    p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    p.bus = &"SFX"
    add_child(p)
    _pool_3d.append(p)

  # Pool of 2D players for rapid UI clicks — lets overlapping clicks
  # fully sound instead of each new one cutting the previous one short.
  # Single-player playback is what was masking the pentatonic chain on
  # fast click streams — every new click was stopping the previous one
  # before the pitch change became audible.
  for i in range(POOL_SIZE_UI):
    var up := AudioStreamPlayer.new()
    # Per-voice volume_db is fine as a static offset; the big "UI is
    # too loud" knob is the SFX bus on SettingsManager.
    up.volume_db = -6.0
    up.bus = &"SFX"
    add_child(up)
    _pool_ui.append(up)

  # Auto-hook: every BaseButton in the scene tree gets a click sound on
  # `pressed`. Connects existing buttons + watches node_added so buttons
  # loaded later (dialogs, dynamically-built panels) also get wired.
  get_tree().node_added.connect(_on_tree_node_added)
  _hook_existing_buttons(get_tree().root)

  # Toast requested → severity-mapped chime. show_toast already routes
  # every UI message through GameState.toast_requested, so hooking once
  # here gives us per-severity audio for free.
  if GameState.has_signal("toast_requested"):
    GameState.toast_requested.connect(_on_toast_requested)


# ---------------------------------------------------------------------------
# Public API — call these from game code
# ---------------------------------------------------------------------------

func play_explosion(
  pos: Vector3, size_hint: float = 1.0, seed_int: int = 0
) -> void:
  ## `size_hint` 0.25..2.0. Bigger = deeper & longer. `seed_int` 0
  ## means randomised per call (each boom sounds a bit different).
  var stream := _gen_explosion(size_hint, seed_int)
  _play_3d(stream, pos, -3.0)


func play_ui_blip(pitch_mult: float = 1.0) -> void:
  ## Short UI tick/ping. pitch_mult 0.7 = low, 1.0 = default, 1.4 = high.
  var stream := _gen_ui_blip(pitch_mult)
  _play_2d(stream)


## Rapid-click chain state. Each consecutive click inside
## CLICK_CHAIN_WINDOW_MS bumps up one step through the pentatonic scale;
## pause longer than the window and the chain resets. State lives on
## this autoload singleton so it's shared across every button in the
## entire app — clicking different buttons still advances the chain.
##
## 1200ms is generous: it catches "normal UI tempo" click-click-click
## (which at ~1 click/sec was falling outside the old 350ms window
## and resetting every time), while still resetting when the player
## steps away from the UI for a beat.
const CLICK_CHAIN_WINDOW_MS := 1200
# C pentatonic major: root, 2nd, 3rd, 5th, 6th, octave. Skipping the
# 4th and 7th dodges the harmonically-awkward notes so a run through
# the whole scale always sounds pleasant.
const CLICK_PENTATONIC_SEMITONES: Array[int] = [0, 2, 4, 7, 9, 12]
var _click_chain_step: int = 0
var _last_click_time_ms: int = -100000


func play_click(pitch_mult: float = 1.0) -> void:
  ## Short mechanical click — default UI button-press sound. Rapid
  ## successive clicks walk up a pentatonic scale for a "building"
  ## feel; pausing (>CLICK_CHAIN_WINDOW_MS) resets to the root.
  var now_ms: int = Time.get_ticks_msec()
  if now_ms - _last_click_time_ms < CLICK_CHAIN_WINDOW_MS:
    _click_chain_step = (_click_chain_step + 1) \
      % CLICK_PENTATONIC_SEMITONES.size()
  else:
    _click_chain_step = 0
  _last_click_time_ms = now_ms

  var semitones: int = CLICK_PENTATONIC_SEMITONES[_click_chain_step]
  var chain_mult: float = pow(2.0, float(semitones) / 12.0)
  var stream := _gen_click(pitch_mult * chain_mult)
  _play_2d(stream, -12.0)


func play_close() -> void:
  ## Distinct low-pitched tick for closing panels / dialogs / dismissals.
  ## Intentionally doesn't participate in the click chain — closing
  ## should always feel like "a thing went down" regardless of rhythm.
  var stream := _gen_click(0.55)
  _play_2d(stream, -12.0)


func play_confirm() -> void:
  ## Rising two-tone (fifth up) — success / accept. Used by green
  ## toasts and other "something good happened" events.
  var stream := _gen_two_tone(660.0, 990.0, 0.06, 0.015)
  _play_2d(stream, -8.0)


func play_deny() -> void:
  ## Falling two-tone — denial / error. Used by red danger toasts.
  var stream := _gen_two_tone(440.0, 294.0, 0.08, 0.02)
  _play_2d(stream, -8.0)


func play_warn() -> void:
  ## Double-beep at the same pitch — urgent but not "wrong". Used by
  ## amber warning toasts.
  var stream := _gen_two_tone(550.0, 550.0, 0.05, 0.03)
  _play_2d(stream, -8.0)


func play_select() -> void:
  ## Soft chime for entity selection. Gentler than a click.
  var stream := _gen_ui_blip(1.25)
  _play_2d(stream, -14.0)


# ---------------------------------------------------------------------------
# Signal hooks (button presses, toast requests)
# ---------------------------------------------------------------------------

func _on_tree_node_added(node: Node) -> void:
  if node is BaseButton:
    # Defer so any `text`/`name` assignment that runs AFTER `add_child`
    # has time to settle — otherwise the "is this a close button?"
    # heuristic below misfires on programmatically-built buttons that
    # go `.new() → add_child → .text = "X"`.
    call_deferred(&"_hook_button", node)


func _hook_existing_buttons(root: Node) -> void:
  if root is BaseButton:
    _hook_button(root)
  for c in root.get_children():
    _hook_existing_buttons(c)


func _hook_button(btn: BaseButton) -> void:
  if not is_instance_valid(btn):
    return
  # Close buttons wear two signatures in this project: either named
  # with "Close" in them (CloseButton, close_button) or plain text "X".
  # Either one gets play_close; everything else is a regular click.
  var is_close: bool = (
    btn.text == "X"
    or "close" in btn.name.to_lower()
  )
  var target: Callable = play_close if is_close else play_click
  # Dedupe against BOTH possible hooks — if a button's text changes
  # from a plain label to "X" later, we still won't double-connect.
  if btn.pressed.is_connected(play_click) \
      or btn.pressed.is_connected(play_close):
    return
  btn.pressed.connect(target)


func _on_toast_requested(_message: String, color: Color) -> void:
  ## ThemePalette colors identify severity. Compare with some float
  ## slop since the signal might ship a slightly-modulated color.
  if color.is_equal_approx(ThemePalette.DANGER):
    play_deny()
  elif color.is_equal_approx(ThemePalette.SUCCESS):
    play_confirm()
  elif color.is_equal_approx(ThemePalette.WARN):
    play_warn()
  else:
    # Info / default — use the select chime so it doesn't feel "loud".
    play_select()


# ---------------------------------------------------------------------------
# Pool dispatch
# ---------------------------------------------------------------------------

func _play_3d(
  stream: AudioStreamWAV, pos: Vector3, db: float = 0.0
) -> void:
  var p: AudioStreamPlayer3D = _pool_3d[_pool_idx]
  _pool_idx = (_pool_idx + 1) % POOL_SIZE_3D
  p.stop()
  p.stream = stream
  p.global_position = pos
  p.volume_db = db
  p.play()


func _play_2d(stream: AudioStreamWAV, db: float = -6.0) -> void:
  ## Round-robin through the UI pool so overlapping clicks can sound
  ## simultaneously. Without this, _ui_player.stop() on every call
  ## truncated each click before its full waveform played — which is
  ## what masked pentatonic chain pitch changes on fast button presses.
  var p: AudioStreamPlayer = _pool_ui[_pool_ui_idx]
  _pool_ui_idx = (_pool_ui_idx + 1) % POOL_SIZE_UI
  p.stop()
  p.stream = stream
  p.volume_db = db
  p.play()


# ---------------------------------------------------------------------------
# Sound generators
# ---------------------------------------------------------------------------

func _gen_explosion(
  size_hint: float, seed_int: int
) -> AudioStreamWAV:
  ## Two-layer synth: a pitch-sweeping low-frequency sine "rumble" plus
  ## a fast-decaying white noise "crack". LFO wobble on the rumble
  ## pitch adds texture so it doesn't read as a pure test-tone.
  var rng := RandomNumberGenerator.new()
  if seed_int == 0:
    rng.randomize()
  else:
    rng.seed = seed_int

  var size := clampf(size_hint, 0.25, 2.0)
  var duration: float = clampf(0.65 + size * 0.35, 0.5, 1.5)
  var n_samples := int(SAMPLE_RATE * duration)
  var pcm := PackedByteArray()
  pcm.resize(n_samples * 2)

  # Rumble pitch inverse-scales with size — huge explosions are bassier.
  # 280 Hz → 45 Hz at size=1, shifted down by ~sqrt(size) for larger.
  var rf_start: float = 280.0 / sqrt(size + 0.3)
  var rf_end: float = 40.0 / sqrt(size + 0.3)
  var rumble_phase: float = 0.0
  var lfo_phase: float = 0.0
  var lfo_freq: float = 5.0

  # Noise envelope decays faster than the rumble envelope — crack up
  # front, rumble tails out. Both tuned experimentally.
  var rumble_decay: float = 2.2 / size     # slower tail for bigger bangs
  var noise_decay: float = 6.0

  for i in range(n_samples):
    var t: float = float(i) / float(n_samples)

    # Pitch LFO wobble (±8 Hz wobble at `lfo_freq`) → non-static rumble.
    lfo_phase += TAU * lfo_freq / float(SAMPLE_RATE)
    var wobble: float = sin(lfo_phase) * 8.0

    var rumble_f: float = lerpf(rf_start, rf_end, pow(t, 0.5)) + wobble
    rumble_phase += TAU * rumble_f / float(SAMPLE_RATE)
    var rumble: float = sin(rumble_phase) * exp(-t * rumble_decay)

    var noise: float = rng.randf_range(-1.0, 1.0)
    var noise_amp: float = exp(-t * noise_decay)

    # Mix. Slight soft-clip via tanh-approximation so the peak crack
    # doesn't hard-clip into a buzz.
    var mixed: float = rumble * 0.55 + noise * noise_amp * 0.85
    var s: float = mixed / (1.0 + abs(mixed) * 0.5)  # cheap soft-clip
    s = clampf(s * 0.85, -1.0, 1.0)

    pcm.encode_s16(i * 2, int(s * 32767.0))

  var wav := AudioStreamWAV.new()
  wav.format = AudioStreamWAV.FORMAT_16_BITS
  wav.mix_rate = SAMPLE_RATE
  wav.stereo = false
  wav.data = pcm
  return wav


func _gen_click(pitch_mult: float) -> AudioStreamWAV:
  ## Short mechanical click: square wave with ~1ms attack and abrupt
  ## release, lower-passed by summing with a sine so it doesn't buzz.
  ## Shorter than `_gen_ui_blip` so rapid presses don't overlap.
  var duration: float = 0.055
  var n_samples := int(SAMPLE_RATE * duration)
  var pcm := PackedByteArray()
  pcm.resize(n_samples * 2)

  var freq: float = 1200.0 * pitch_mult
  var phase: float = 0.0
  var attack_n: int = int(0.0015 * SAMPLE_RATE)
  var release_start: int = n_samples - int(0.015 * SAMPLE_RATE)

  for i in range(n_samples):
    phase += TAU * freq / float(SAMPLE_RATE)
    var s_val: float = sin(phase)
    # Square-heavy wave for the "tick" character, softened with sine
    # so it doesn't read as harsh DC.
    var wave: float = sign(s_val) * 0.35 + s_val * 0.25

    var env: float = 1.0
    if i < attack_n:
      env = float(i) / float(attack_n)
    elif i > release_start:
      env = 1.0 - float(i - release_start) / float(
        n_samples - release_start
      )

    var s: float = wave * env * 0.5
    pcm.encode_s16(i * 2, int(s * 32767.0))

  var wav := AudioStreamWAV.new()
  wav.format = AudioStreamWAV.FORMAT_16_BITS
  wav.mix_rate = SAMPLE_RATE
  wav.stereo = false
  wav.data = pcm
  return wav


func _gen_two_tone(
  f1: float, f2: float, tone_dur: float, gap: float
) -> AudioStreamWAV:
  ## Two sequential tones (`f1` then `f2`) with a brief gap between.
  ## Each tone is a sine+square mix with attack/release envelope.
  ## Used for confirm / deny / warn cues.
  var total_dur: float = tone_dur * 2.0 + gap
  var n_samples := int(SAMPLE_RATE * total_dur)
  var pcm := PackedByteArray()
  pcm.resize(n_samples * 2)

  var tone_samples := int(tone_dur * SAMPLE_RATE)
  var gap_samples := int(gap * SAMPLE_RATE)
  var attack_n: int = int(0.004 * SAMPLE_RATE)
  var release_n: int = int(0.018 * SAMPLE_RATE)
  var phase: float = 0.0

  for i in range(n_samples):
    # Figure out which segment we're in: tone1, gap, tone2.
    var freq: float = 0.0
    var local_i: int = 0
    var local_n: int = tone_samples
    if i < tone_samples:
      freq = f1
      local_i = i
    elif i < tone_samples + gap_samples:
      freq = 0.0
    else:
      freq = f2
      local_i = i - (tone_samples + gap_samples)
      # Reset phase on tone boundary for a cleaner attack.
      if local_i == 0:
        phase = 0.0

    if freq <= 0.0:
      pcm.encode_s16(i * 2, 0)
      continue

    phase += TAU * freq / float(SAMPLE_RATE)
    var s_val: float = sin(phase)
    var wave: float = s_val * 0.55 + sign(s_val) * 0.18

    var env: float = 1.0
    if local_i < attack_n:
      env = float(local_i) / float(attack_n)
    elif local_i > local_n - release_n:
      env = 1.0 - float(local_i - (local_n - release_n)) / float(release_n)
    env = clampf(env, 0.0, 1.0)

    var s: float = wave * env * 0.5
    pcm.encode_s16(i * 2, int(s * 32767.0))

  var wav := AudioStreamWAV.new()
  wav.format = AudioStreamWAV.FORMAT_16_BITS
  wav.mix_rate = SAMPLE_RATE
  wav.stereo = false
  wav.data = pcm
  return wav


func _gen_ui_blip(pitch_mult: float) -> AudioStreamWAV:
  ## Short ping: triangle/square mix with a 4ms attack + 40ms release.
  ## The square layer gives it a bit of chiptune crunch.
  var duration: float = 0.10
  var n_samples := int(SAMPLE_RATE * duration)
  var pcm := PackedByteArray()
  pcm.resize(n_samples * 2)

  var freq: float = 880.0 * pitch_mult
  var phase: float = 0.0
  var attack_n: int = int(0.004 * SAMPLE_RATE)
  var release_start: int = n_samples - int(0.040 * SAMPLE_RATE)

  for i in range(n_samples):
    phase += TAU * freq / float(SAMPLE_RATE)
    var s_val: float = sin(phase)
    var wave: float = s_val * 0.55 + sign(s_val) * 0.18

    var env: float = 1.0
    if i < attack_n:
      env = float(i) / float(attack_n)
    elif i > release_start:
      env = 1.0 - float(i - release_start) / float(
        n_samples - release_start
      )

    var s: float = wave * env * 0.55
    pcm.encode_s16(i * 2, int(s * 32767.0))

  var wav := AudioStreamWAV.new()
  wav.format = AudioStreamWAV.FORMAT_16_BITS
  wav.mix_rate = SAMPLE_RATE
  wav.stereo = false
  wav.data = pcm
  return wav
