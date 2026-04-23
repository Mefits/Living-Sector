extends Node

## Lifecycle manager for the bundled simulator subprocess.
##
## Flow (explicit — no probe-based guessing):
##   1. `start(on_ready)` checks SPACESIM_USE_EXISTING_SERVER.
##      - Truthy: skip spawn, poll /api/health until it answers (dev).
##      - Otherwise: spawn the bundled Rust `simulator` binary, then
##        poll /api/health on the fixed bind port.
##   2. Poll /api/health every ~150 ms up to READY_TIMEOUT_SEC. First
##      200 ⇒ ready.
##   3. `_process` watches the spawned PID; if the process dies
##      unexpectedly, emits `server_died` so the game can return to the
##      main menu. Dev mode (external server) never spawned a PID so
##      this path is naturally skipped.
##   4. On app exit (`_exit_tree` / WM_CLOSE_REQUEST), SIGTERM the
##      subprocess, wait up to SHUTDOWN_GRACE_SEC, SIGKILL if still
##      alive. The Rust sim handles SIGTERM by flushing its persistence
##      worker (~up to 1 s) then exiting cleanly, so 2 s of grace is
##      comfortable.
##
## The prior implementation wrapped an Elixir `mix release ... daemon`
## spawn — that needed a port.txt sidecar (BEAM picked a free port),
## a beam.pid sidecar (run_erl detached the daemon), RELEASE_TMP +
## ERL_FLAGS env, etc. The Rust sim is a single native binary that
## binds a known port, runs as our direct child, and responds to
## POSIX signals normally, so all that machinery is gone.

signal server_died(reason: String)

# Was "localhost". On Windows, `localhost` resolves to `::1, 127.0.0.1` and
# Godot's HTTPRequest picks the first address (IPv6) without happy-eyeballs
# fallback. The sim binds `127.0.0.1` (see BIND_ADDR in _spawn_and_begin_poll),
# so IPv6 probes SYN into a black hole and time out. Pinning to the same
# family the sim binds to makes the probe actually reach it.
const DEFAULT_HOST := "127.0.0.1"
# Port 8080 is the Rust simulator's default (simulator-rust/). The
# legacy Elixir sim used 4000; set SPACESIM_TARGET_ELIXIR=1 combined
# with SPACESIM_USE_EXISTING_SERVER=1 to connect to an externally-
# started Elixir sim for backward-compat testing.
const DEFAULT_PORT := 8080
const ELIXIR_PORT := 4000
const READY_POLL_INTERVAL := 0.15
# Cold-boot of the Rust sim is ~1 s locally; packaged builds add
# Gatekeeper / codesign verification + first-run DB migrations.
# 15 s is comfortable headroom without tying up a hung startup.
const READY_TIMEOUT_SEC := 15.0
# Crash watchdog cadence. Relies on _pid_alive (kill -0 / tasklist)
# since OS.is_process_running only works for direct children.
const CRASH_POLL_INTERVAL := 5.0
const SHUTDOWN_GRACE_SEC := 2.0

enum State { IDLE, SPAWNING, POLLING_READY }

var last_error: String = ""
# True when SPACESIM_USE_EXISTING_SERVER told us to skip spawning.
# Used to gate crash detection so a dev-side server restart doesn't
# punt us back to the main menu.
var _using_existing_server: bool = false

var _host: String = DEFAULT_HOST
var _port: int = DEFAULT_PORT
# Swap to the Elixir port when env asks for the legacy simulator.
var _target_elixir: bool = false
var _pid: int = -1
# Absolute path to the .db the sim should open. Defaults to
# user_data_dir/sim.db; load-save flow swaps this in before spawn.
var _database_path: String = ""

var _ready_http: HTTPRequest
var _ready_callback: Callable
var _ready_deadline: float = 0.0
var _ready_in_flight: bool = false
var _state: int = State.IDLE

var _crash_timer: float = 0.0


func _ready() -> void:
  # Env override for targeting the legacy Elixir simulator (port 4000).
  # Only meaningful alongside SPACESIM_USE_EXISTING_SERVER=1 — we don't
  # spawn BEAM from here anymore.
  if _env_truthy("SPACESIM_TARGET_ELIXIR") \
      or _dev_env_truthy("SPACESIM_TARGET_ELIXIR"):
    _target_elixir = true
    _port = ELIXIR_PORT
    print(
      "[ServerManager] SPACESIM_TARGET_ELIXIR=1 — expecting external "
      + "Elixir sim on port %d" % _port
    )
  else:
    print(
      "[ServerManager] targeting Rust simulator on port %d" % _port
    )
  _ready_http = HTTPRequest.new()
  # Localhost round-trip is sub-ms in steady state, but the very first
  # request after a process spawn can take longer while the HTTP
  # server warms up. 5 s is generous.
  _ready_http.timeout = 5.0
  _ready_http.request_completed.connect(_on_ready_probe_completed)
  add_child(_ready_http)
  # Trail of breadcrumbs that's priceless when diagnosing a packaged
  # build — pair with project.godot's [debug] file_logging, which
  # redirects this to user://logs/client.log.
  print(
    "[ServerManager] exe_dir=%s"
    % OS.get_executable_path().get_base_dir()
  )
  print("[ServerManager] user_data_dir=%s" % OS.get_user_data_dir())


# -------- Public API --------

func host() -> String:
  return _host


func port() -> int:
  return _port


func is_spawned() -> bool:
  return _pid > 0


func is_using_existing_server() -> bool:
  return _using_existing_server


func saves_dir() -> String:
  ## Where the sim writes its .db files. Default is the Godot
  ## user_data_dir; the sim uses DATABASE_PATH to locate the active
  ## one and writes save-as copies as siblings of that file.
  return OS.get_user_data_dir()


func default_database_path() -> String:
  return saves_dir().path_join("sim.db")


func current_database_path() -> String:
  if _database_path != "":
    return _database_path
  return default_database_path()


func database_path_for_name(save_name: String) -> String:
  ## Resolve a bare save name like "campaign1" into a full database
  ## path under `saves_dir()`. Sanitises the name aggressively so
  ## arbitrary user input can never escape the saves directory.
  ## Always appends `.db`.
  if save_name == "":
    return default_database_path()
  var clean := _sanitize_save_name(save_name)
  if clean == "":
    clean = "untitled"
  return saves_dir().path_join(clean + ".db")


const _MAX_SAVE_NAME_LEN := 100


func _sanitize_save_name(raw: String) -> String:
  ## Whitelist: a-z, A-Z, 0-9, `-`, `_`. Everything else (including
  ## `/`, `\`, `.`, space, control chars, non-ASCII) becomes an
  ## underscore. Doubled/leading/trailing underscores are collapsed.
  ## A user-typed `.db` suffix is stripped before sanitisation so we
  ## don't end up with ugly names like `mysave_db.db`.
  var name := raw.strip_edges()
  if name.to_lower().ends_with(".db"):
    name = name.substr(0, name.length() - 3)

  var out := ""
  for i in range(name.length()):
    var c := name[i]
    if (c >= "a" and c <= "z") \
        or (c >= "A" and c <= "Z") \
        or (c >= "0" and c <= "9") \
        or c == "-" or c == "_":
      out += c
    else:
      out += "_"

  # Collapse runs of underscores so `david///game` doesn't land as
  # `david___game` — reads as `david_game` which is what a human
  # would type anyway.
  while "__" in out:
    out = out.replace("__", "_")

  # Strip leading / trailing underscores so names don't look accidental
  # (`_david_` → `david`).
  while out.begins_with("_"):
    out = out.substr(1)
  while out.ends_with("_"):
    out = out.substr(0, out.length() - 1)

  # Filesystem-safety cap. Most FSes allow 255; 100 is a comfortable
  # ceiling that keeps the full path (incl. saves_dir) well short of
  # the OS PATH_MAX.
  if out.length() > _MAX_SAVE_NAME_LEN:
    out = out.substr(0, _MAX_SAVE_NAME_LEN)

  return out


func start(on_ready: Callable, save_name: String = "") -> void:
  ## `save_name` is always treated as a bare name and always lands
  ## inside `saves_dir()`. No absolute-path escape hatch — the user
  ## can only pick which file inside our saves folder, never arbitrary
  ## locations on disk.
  ##   - ""              → default sim.db under saves_dir()
  ##   - "my_campaign"   → saves_dir()/my_campaign.db
  ##   - "david/game"    → saves_dir()/david_game.db   (sanitised)
  ##   - "../../etc"     → saves_dir()/etc.db          (sanitised)
  ##
  ## Names are whitelisted to [a-zA-Z0-9_-]; anything else collapses
  ## to `_`. Guarantees user input never digs out of saves_dir.
  if _state != State.IDLE:
    push_error("[ServerManager] start() called while state=%d" % _state)
    return
  last_error = ""
  _using_existing_server = false
  _ready_callback = on_ready
  _database_path = (
    default_database_path() if save_name == ""
    else database_path_for_name(save_name)
  )
  print(
    "[ServerManager] start(save_name=%s) → database_path=%s"
    % [save_name if save_name != "" else "<default>", _database_path]
  )

  if _should_use_existing_server():
    # Dev mode: don't spawn; wait for whatever's on localhost:port.
    # Crash detection stays off — dev restarts shouldn't menu us out.
    print(
      "[ServerManager] dev mode — waiting for external server at %s:%d"
      % [_host, _port]
    )
    _using_existing_server = true
    _state = State.POLLING_READY
    _ready_deadline = _now() + READY_TIMEOUT_SEC
    _try_ready_probe()
    return

  # Shipped mode: spawn the bundled Rust simulator.
  _state = State.SPAWNING
  _spawn_and_begin_poll()


func _should_use_existing_server() -> bool:
  # Env var wins if set, so CI / explicit shell launches stay
  # authoritative. Otherwise fall back to res://dev.env (a gitignored
  # project-local file) so hitting F5 in the editor works without
  # fiddling with your shell.
  if _env_truthy("SPACESIM_USE_EXISTING_SERVER"):
    return true
  return _dev_env_truthy("SPACESIM_USE_EXISTING_SERVER")


func _dev_env_truthy(key: String) -> bool:
  # Only honor the file when running from the editor. Exported builds
  # — even debug ones — ignore dev.env entirely, so an accidental
  # bundle can't flip a shipped build into dev mode.
  if not OS.has_feature("editor"):
    return false
  var path := "res://dev.env"
  if not FileAccess.file_exists(path):
    return false
  var f := FileAccess.open(path, FileAccess.READ)
  if f == null:
    return false
  while not f.eof_reached():
    var line: String = f.get_line().strip_edges()
    if line == "" or line.begins_with("#"):
      continue
    var eq := line.find("=")
    var k: String
    var v: String
    if eq < 0:
      # Bare key (like `FOO` on its own line) counts as truthy.
      k = line
      v = "1"
    else:
      k = line.substr(0, eq).strip_edges()
      v = line.substr(eq + 1).strip_edges()
    if k == key:
      var low := v.to_lower()
      return (
        v != "" and low != "0" and low != "false" and low != "no"
      )
  return false


func stop() -> void:
  if _pid <= 0:
    return
  var pid := _pid
  _pid = -1  # clear before we kill so the crash watchdog won't fire
  print("[ServerManager] Stopping simulator pid=%d" % pid)
  _send_terminate_signal(pid)
  var deadline := _now() + SHUTDOWN_GRACE_SEC
  # Use _pid_alive rather than OS.is_process_running because the latter
  # relies on waitpid, which can return early/wrong depending on how
  # the child was launched (daemon-vs-direct). kill -0 is unambiguous.
  while _pid_alive(pid):
    if _now() >= deadline:
      print(
        "[ServerManager] force-kill pid=%d (grace expired)" % pid
      )
      OS.kill(pid)
      break
    OS.delay_msec(200)


func _send_terminate_signal(pid: int) -> void:
  # Godot 4's OS.kill(pid) is forceful on every platform (SIGKILL /
  # TerminateProcess). For graceful shutdown we shell out so the
  # Rust sim's signal handler can flush its persistence worker +
  # close WAL cleanly before exit.
  match OS.get_name():
    "Windows":
      # taskkill without /F asks the process to exit; if it doesn't,
      # the grace loop below falls back to OS.kill(pid).
      OS.execute("taskkill", ["/PID", str(pid)])
    _:
      OS.execute("kill", ["-TERM", str(pid)])


# -------- Lifecycle --------

func _exit_tree() -> void:
  stop()


func _notification(what: int) -> void:
  if what == NOTIFICATION_WM_CLOSE_REQUEST:
    stop()


func _process(delta: float) -> void:
  # Gate on State.IDLE so the watchdog only runs post-startup.
  if _pid <= 0 or _state != State.IDLE:
    return
  _crash_timer += delta
  if _crash_timer < CRASH_POLL_INTERVAL:
    return
  _crash_timer = 0.0
  if not _pid_alive(_pid):
    var dead_pid := _pid
    _pid = -1
    var reason := "simulator subprocess exited (pid %d)" % dead_pid
    last_error = reason
    server_died.emit(reason)


func _pid_alive(pid: int) -> bool:
  # POSIX existence check — works whether the child is direct or
  # detached. Rust sim runs as a direct child so OS.is_process_running
  # would also work, but `kill -0` is simpler and platform-agnostic
  # with the Windows branch below.
  if pid <= 0:
    return false
  if OS.get_name() == "Windows":
    var out: Array = []
    var code := OS.execute(
      "tasklist",
      ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"],
      out
    )
    if code != 0:
      return false
    return str(out).contains(str(pid))
  var exit_code := OS.execute("kill", ["-0", str(pid)])
  return exit_code == 0


# -------- Ready probe / polling state machine --------

func _try_ready_probe() -> void:
  if _ready_in_flight:
    return
  var url := "http://%s:%d/api/health" % [_host, _port]
  _ready_in_flight = true
  var err := _ready_http.request(url)
  if err != OK:
    _ready_in_flight = false
    _on_probe_network_error(err)


func _on_ready_probe_completed(
  result: int, response_code: int,
  _headers: PackedStringArray, _body: PackedByteArray
) -> void:
  _ready_in_flight = false
  # result != RESULT_SUCCESS means the request itself didn't complete.
  # That's expected while the sim is still booting — retry.
  var probe_ok: bool = (
    result == HTTPRequest.RESULT_SUCCESS and response_code == 200
  )
  if not probe_ok:
    print(
      "[ServerManager] probe failed: result=%d response_code=%d"
      % [result, response_code]
    )

  match _state:
    State.POLLING_READY:
      if probe_ok:
        print(
          "[ServerManager] Server ready at %s:%d" % [_host, _port]
        )
        _finish_start(OK)
      elif _now() >= _ready_deadline:
        _dump_startup_postmortem()
        _fail_start(
          "timed out waiting for /api/health (%.0fs)"
          % READY_TIMEOUT_SEC
        )
      else:
        _schedule_next_probe()
    _:
      pass


func _on_probe_network_error(err: int) -> void:
  # HTTPRequest.request() rejected the call (bad URL, already in flight,
  # etc.) — shouldn't happen given our state machine, but treat as a
  # probe failure and keep going if we still have time.
  if _state == State.POLLING_READY and _now() < _ready_deadline:
    _schedule_next_probe()
  else:
    _fail_start("HTTP request error: %d" % err)


func _schedule_next_probe() -> void:
  var t := get_tree().create_timer(READY_POLL_INTERVAL)
  t.timeout.connect(_try_ready_probe, CONNECT_ONE_SHOT)


# -------- Spawn --------

func _spawn_and_begin_poll() -> void:
  var binary := _resolve_server_binary()
  if binary == "":
    _fail_start(
      "simulator binary not found "
      + "(set SPACESIM_SERVER_PATH to override)"
    )
    return
  # Env setup for the Rust sim: DATABASE_PATH points at the specific
  # SQLite file the load-save flow selected, BIND_ADDR pins the port
  # so we don't need a port-discovery handshake, SPACESIM_PARENT_PID
  # arms the sim's parent watchdog so a Godot crash takes the sim
  # down with it instead of leaving an orphan bound to the port, and
  # RUST_LOG gets info tracing if unset.
  DirAccess.make_dir_recursive_absolute(_database_path.get_base_dir())
  OS.set_environment("DATABASE_PATH", _database_path)
  OS.set_environment("BIND_ADDR", "127.0.0.1:%d" % _port)
  OS.set_environment("SPACESIM_PARENT_PID", str(OS.get_process_id()))
  if OS.get_environment("RUST_LOG") == "":
    OS.set_environment(
      "RUST_LOG", "simulator=info,sim_core=info,tower_http=warn"
    )

  print(
    "[ServerManager] env DATABASE_PATH=%s"
    % OS.get_environment("DATABASE_PATH")
  )
  print(
    "[ServerManager] env BIND_ADDR=%s"
    % OS.get_environment("BIND_ADDR")
  )
  print(
    "[ServerManager] env SPACESIM_PARENT_PID=%s"
    % OS.get_environment("SPACESIM_PARENT_PID")
  )
  print("[ServerManager] Spawning: %s (db=%s)" % [binary, _database_path])

  # Direct exec — no sh wrapper. The prior BEAM path used /bin/sh for
  # ulimit, cd to release root, run_erl detachment, and stdout capture.
  # Rust is a static single-binary server with no external tool deps
  # and no pipe-fill issue (tracing writes through a normal buffered
  # writer), so plain OS.create_process is enough and dodges the
  # sandbox / Gatekeeper friction that shell invocations attract on
  # macOS.
  var pid := OS.create_process(binary, [], false)
  if pid <= 0:
    _fail_start("OS.create_process failed for %s" % binary)
    return
  _pid = pid
  print("[ServerManager] Spawned simulator pid=%d" % _pid)

  # macOS: clear the inherited "background" QoS class on the child.
  # A .app launched from Finder/LaunchServices runs at a background
  # QoS that propagates to child processes; Apple Silicon then pins
  # those threads to E-cores. For the Rust sim that manifests as
  # apparent-busy (tokio workers at 100%) but 5–10× slower tick rate.
  # Same symptom we saw with BEAM under the Elixir sim — the fix is
  # the same because it's a kernel-level inheritance, not runtime-
  # specific.
  _clear_background_qos_if_macos(_pid)

  # Port is fixed (we set BIND_ADDR), so we go straight to polling
  # /api/health.
  _state = State.POLLING_READY
  _ready_deadline = _now() + READY_TIMEOUT_SEC
  _try_ready_probe()


func _clear_background_qos_if_macos(pid: int) -> void:
  ## `taskpolicy -B -p <pid>` clears the background QoS flag on an
  ## existing pid. The `-B` flag is `-p`-only per the man page —
  ## can't be combined with `-c` to wrap a new program, which is why
  ## we call it post-spawn rather than via shell wrapping.
  ##
  ## Harmless (exit 0) when nothing was set, so safe to call
  ## unconditionally on macOS. `taskpolicy -c user-interactive` was
  ## explored earlier for wrap-mode but it's demote-only (utility /
  ## background / maintenance), can't promote.
  if OS.get_name() != "macOS":
    return
  var out: Array = []
  var code := OS.execute(
    "/usr/sbin/taskpolicy", ["-B", "-p", str(pid)], out, true
  )
  if code == 0:
    print("[ServerManager] taskpolicy -B -p %d → OK" % pid)
  else:
    push_warning(
      "[ServerManager] taskpolicy -B failed code=%d out=%s"
      % [code, "".join(out)]
    )


func _dump_startup_postmortem() -> void:
  # Timed out waiting for /api/health — dump what we have. With the
  # direct-exec path we no longer capture stderr to a file, but the
  # pid-alive state and resolved binary path still narrow down the
  # "didn't start" vs "crashed early" vs "slow boot" distinction.
  print("[ServerManager] postmortem: saves_dir=%s" % saves_dir())
  if _pid > 0:
    var alive: bool = _pid_alive(_pid)
    print(
      "[ServerManager] postmortem: sim pid=%d alive=%s"
      % [_pid, alive]
    )
  else:
    print("[ServerManager] postmortem: no pid (spawn never succeeded)")


func _resolve_server_binary() -> String:
  # Try each candidate in order; first one whose binary exists wins.
  # Log every candidate + outcome so packaged builds leave a trail.
  for candidate in _binary_candidates():
    var exists: bool = FileAccess.file_exists(candidate)
    print(
      "[ServerManager] candidate %s → %s"
      % [candidate, "FOUND" if exists else "missing"]
    )
    if exists:
      return candidate
  return ""


func _binary_candidates() -> Array[String]:
  var out: Array[String] = []
  var exe_suffix: String = ".exe" if OS.get_name() == "Windows" else ""
  var binary_name := "simulator%s" % exe_suffix

  # 1. Explicit env override wins.
  var override := OS.get_environment("SPACESIM_SERVER_PATH")
  if override != "":
    out.append(override)

  var exe_dir := OS.get_executable_path().get_base_dir()

  # 2. Shipped next to the game binary (Windows / Linux layout, and
  #    macOS if the export preset puts non-resource files in
  #    Contents/MacOS).
  out.append(exe_dir.path_join(binary_name))

  # 3. macOS .app bundle: non-resource files typically land under
  #    Contents/Resources/. exe_dir is Contents/MacOS.
  if OS.get_name() == "macOS":
    out.append(
      exe_dir.path_join("..").path_join("Resources").path_join(binary_name)
    )

  # 4. In-project drop (dev or editor run when a built binary has
  #    been copied to res://simulator for export testing).
  out.append(
    ProjectSettings.globalize_path("res://%s" % binary_name)
  )

  # 5. Sibling Rust project's release build — the default dev path
  #    when running via `cargo build --release`.
  out.append(
    ProjectSettings.globalize_path(
      "res://../simulator-rust/target/release/%s" % binary_name
    )
  )

  # 6. Rust debug build — last-resort fallback so hitting F5 in the
  #    editor works even if the user hasn't built release yet.
  out.append(
    ProjectSettings.globalize_path(
      "res://../simulator-rust/target/debug/%s" % binary_name
    )
  )

  return out


# -------- Start callback plumbing --------

func _finish_start(status: int) -> void:
  _state = State.IDLE
  var cb := _ready_callback
  _ready_callback = Callable()
  if cb.is_valid():
    cb.call(status, "")


func _fail_start(reason: String) -> void:
  last_error = reason
  push_error("[ServerManager] Start failed: %s" % reason)
  _state = State.IDLE
  var cb := _ready_callback
  _ready_callback = Callable()
  if cb.is_valid():
    cb.call(FAILED, reason)


# -------- Helpers --------

func _env_truthy(key: String) -> bool:
  var v := OS.get_environment(key)
  if v == "":
    return false
  var low := v.to_lower()
  return low != "0" and low != "false" and low != "no"


func _now() -> float:
  return Time.get_unix_time_from_system()
