extends Node

## Lifecycle manager for the bundled simulator subprocess.
##
## Flow (explicit — no probe-based guessing):
##   1. `start(on_ready)` checks SPACESIM_USE_EXISTING_SERVER.
##      - Truthy: skip spawn, poll /api/health until it answers (dev).
##      - Otherwise: spawn the bundled BEAM release, then poll.
##   2. Poll /api/health every ~150 ms up to 15 s. First 200 ⇒ ready.
##   3. `_process` watches the spawned PID; if the process dies
##      unexpectedly, emits `server_died` so the game can return to the
##      main menu. Dev mode (external server) never spawned a PID so
##      this path is naturally skipped.
##   4. On app exit (`_exit_tree` / WM_CLOSE_REQUEST), SIGTERM the
##      subprocess, wait up to 2 s, SIGKILL if still alive.

signal server_died(reason: String)

const DEFAULT_HOST := "localhost"
# Port 8080 is the Rust simulator's default (simulator-rust/). The old
# Elixir sim used 4000; set SPACESIM_TARGET_ELIXIR=1 to restore that for
# legacy use. With `SPACESIM_USE_EXISTING_SERVER=1` the client skips
# spawning and talks to whichever simulator is already listening on this
# port.
const DEFAULT_PORT := 8080
const ELIXIR_PORT := 4000
const READY_POLL_INTERVAL := 0.15
# Cold-boot of the packaged BEAM can be slow — migrations, seeding from
# JSON, spawning ~350 agents — especially under macOS QoS clamp on a
# GUI-spawned child. 15 s was tight; 60 s is comfortable headroom.
const READY_TIMEOUT_SEC := 15.0
# Each check forks a `kill -0` / `tasklist` (since waitpid doesn't work
# on non-child daemon pids — see _pid_alive). 5 s is plenty — if BEAM
# crashes, HTTP/WS errors surface the problem faster anyway.
const CRASH_POLL_INTERVAL := 5.0
const SHUTDOWN_GRACE_SEC := 2.0

enum State { IDLE, SPAWNING, WAITING_PORT, POLLING_READY }

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
# The sim binds to port 0 (OS-assigned free port) and writes the
# chosen port to <saves_dir>/port.txt. We poll that file after spawn
# before trying /api/health.
var _port_file_path: String = ""
# `mix release … daemon` writes its PID here (under RELEASE_TMP). We
# read it after port.txt appears and replace _pid with the daemon's
# real PID — our sh wrapper's pid exits seconds after forking.
var _pid_file_path: String = ""

var _ready_http: HTTPRequest
var _ready_callback: Callable
var _ready_deadline: float = 0.0
var _ready_in_flight: bool = false
var _state: int = State.IDLE

var _crash_timer: float = 0.0


func _ready() -> void:
  # Env override for targeting the legacy Elixir simulator (port 4000).
  if _env_truthy("SPACESIM_TARGET_ELIXIR") or _dev_env_truthy("SPACESIM_TARGET_ELIXIR"):
    _target_elixir = true
    _port = ELIXIR_PORT
    print("[ServerManager] SPACESIM_TARGET_ELIXIR=1 — using Elixir port %d" % _port)
  else:
    print("[ServerManager] targeting Rust simulator on port %d" % _port)
  _ready_http = HTTPRequest.new()
  # 5s — localhost round-trip is sub-ms in steady state, but the very
  # first request after a process spawn sometimes takes a bit longer
  # while Phoenix's connection pool warms up. 1s was tripping on
  # packaged macOS builds even though the server was healthy.
  _ready_http.timeout = 5.0
  _ready_http.request_completed.connect(_on_ready_probe_completed)
  add_child(_ready_http)
  # Trail of breadcrumbs that's priceless when diagnosing a packaged
  # build — pair with project.godot's [debug] file_logging, which
  # redirects this to user://logs/client.log.
  print("[ServerManager] exe_dir=%s" % OS.get_executable_path().get_base_dir())
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
  # return "/Users/dclausen/test/test.db"
  return saves_dir().path_join("sim.db")


func current_database_path() -> String:
  if _database_path != "":
    return _database_path
  return default_database_path()


func start(on_ready: Callable, database_path: String = "") -> void:
  if _state != State.IDLE:
    push_error("[ServerManager] start() called while state=%d" % _state)
    return
  last_error = ""
  _using_existing_server = false
  _ready_callback = on_ready
  # Default DB path unless the caller picked one (load-save flow).
  _database_path = database_path if database_path != "" else default_database_path()

  if _should_use_existing_server():
    # Dev mode: don't spawn; wait for whatever's on localhost:port.
    # Crash detection stays off — dev restarts shouldn't menu us out.
    print("[ServerManager] dev mode — waiting for external server "
      + "at %s:%d" % [_host, _port])
    _using_existing_server = true
    _state = State.POLLING_READY
    _ready_deadline = _now() + READY_TIMEOUT_SEC
    _try_ready_probe()
    return

  # Shipped mode: always spawn the bundled BEAM.
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
      return v != "" and low != "0" and low != "false" and low != "no"
  return false


func stop() -> void:
  if _pid <= 0:
    return
  var pid := _pid
  _pid = -1  # clear before we kill so the crash watchdog won't fire
  print("[ServerManager] Stopping BEAM pid=%d" % pid)
  _send_terminate_signal(pid)
  var deadline := _now() + SHUTDOWN_GRACE_SEC
  # Use _pid_alive (kill -0) not OS.is_process_running — daemon BEAM is
  # detached by run_erl so waitpid errors with ECHILD, which would make
  # us skip the force-kill branch and orphan the BEAM on shutdown.
  while _pid_alive(pid):
    if _now() >= deadline:
      print("[ServerManager] force-kill pid=%d (grace expired)" % pid)
      OS.kill(pid)
      break
    OS.delay_msec(200)


func _send_terminate_signal(pid: int) -> void:
  # Godot 4's OS.kill(pid) is forceful on every platform (SIGKILL /
  # TerminateProcess). For graceful shutdown we shell out so the
  # sim's PersistenceManager can flush + close WAL cleanly.
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
  # Gate on State.IDLE so the watchdog only runs post-startup. During
  # daemon spawn the sh-wrapper pid exits within a second (by design —
  # run_erl forks and detaches), which would otherwise look like a
  # crash before we've read the real daemon pid from the pid file.
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
  # Godot's OS.is_process_running uses waitpid, which errors with
  # ECHILD on any pid that isn't our direct child — and the daemon
  # BEAM isn't: run_erl detached it during spawn. Shell out to a
  # POSIX existence check instead (`kill -0`), which works regardless
  # of parent-child relationship.
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
    # tasklist prints "INFO: No tasks..." when pid missing; a real
    # row contains the pid in a CSV field.
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
  # That's expected while the BEAM is still booting — retry.
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
        print("[ServerManager] Server ready at %s:%d"
          % [_host, _port])
        _finish_start(OK)
      elif _now() >= _ready_deadline:
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
  # Env setup: PARENT_PID for the sim's parent-watchdog, DATABASE_PATH
  # so load-save flow can point at a specific .db, LOG_LEVEL so the
  # sim's Elixir Logger emits info + higher. Inherited by the child
  # since OS.create_process has no env-dict arg.
  OS.set_environment("PARENT_PID", str(OS.get_process_id()))
  DirAccess.make_dir_recursive_absolute(_database_path.get_base_dir())
  OS.set_environment("DATABASE_PATH", _database_path)
  OS.set_environment("LOG_LEVEL", "info")
  # -noinput: stop the BEAM from polling stdin. Eliminates the
  # driver_select / prim_tty warning at startup and a subtle race
  # when stdin is a redirected pipe.
  OS.set_environment("ERL_FLAGS", "-noinput")

  # Packaged .app builds launched from Finder have a minimal PATH
  # (often just /usr/bin:/bin), which can break mix release's launcher
  # script when it invokes awk/grep/etc. Ensure we have standard paths.
  _ensure_path_has_standard_dirs()

  # Dump the env the child will see so packaged-build troubleshooting
  # has the same starting point as "what does your shell look like".
  print("[ServerManager] env PATH=%s" % OS.get_environment("PATH"))
  print("[ServerManager] env HOME=%s" % OS.get_environment("HOME"))
  print("[ServerManager] env USER=%s" % OS.get_environment("USER"))

  # Port + pid sidecars land next to the DB (sim does
  # `Path.dirname(db_path)`). When the active DB lives outside
  # saves_dir — load-save flow, or a dev override — polling
  # saves_dir/port.txt silently misses the file. Follow the DB.
  var sidecar_dir: String = _database_path.get_base_dir()

  # Clean up any stale port.txt from a prior run so we don't read
  # an old port back before the new process overwrites the file.
  _port_file_path = sidecar_dir.path_join("port.txt")
  if FileAccess.file_exists(_port_file_path):
    DirAccess.remove_absolute(_port_file_path)
  # Reset port to default; real value arrives via port.txt.
  _port = DEFAULT_PORT

  # The release bundle sits under a read-only location in a packaged
  # .app (Gatekeeper protects Contents/Resources). `mix release …
  # daemon` uses run_erl, which writes logs under <release>/tmp unless
  # RELEASE_TMP redirects it — point that at a writable dir.
  var release_tmp := saves_dir().path_join("sim_tmp")
  DirAccess.make_dir_recursive_absolute(release_tmp)
  OS.set_environment("RELEASE_TMP", release_tmp)
  # Daemon PID sidecar. run_erl doesn't write a pid file anywhere
  # predictable, so the sim writes its own beam.pid next to port.txt
  # at startup. We read it after the port appears — see
  # _read_daemon_pid_into_self.
  _pid_file_path = sidecar_dir.path_join("beam.pid")
  if FileAccess.file_exists(_pid_file_path):
    DirAccess.remove_absolute(_pid_file_path)

  print("[ServerManager] Spawning: %s (PARENT_PID=%d, db=%s)"
    % [binary, OS.get_process_id(), _database_path])
  var pid := _spawn_child(binary)
  if pid <= 0:
    _fail_start("OS.create_process failed for %s" % binary)
    return
  _pid = pid
  print("[ServerManager] Spawned BEAM pid=%d" % _pid)

  # First wait for the sim to write port.txt (it binds to port 0 and
  # the OS hands back a free port), then poll /api/health on that port.
  _state = State.WAITING_PORT
  _ready_deadline = _now() + READY_TIMEOUT_SEC
  _try_port_file_read()


func _spawn_child(binary: String) -> int:
  # IMPORTANT: redirect child stdout + stderr to a log file.
  #
  # OS.create_process doesn't hand us pipe handles, and Godot doesn't
  # drain them itself. At ~64 KB of unread output the OS pipe buffer
  # fills up and the next write inside the BEAM BLOCKS — mid-request,
  # mid-GenServer, wherever the write happens to land. From terminal
  # a real tty keeps pulling the buffer so this never surfaces; from
  # Godot it reliably stalls the sim a few seconds in. Redirecting to
  # a file sidesteps the pipe entirely and gives us the sim's logs
  # for debugging as a bonus.
  if OS.get_name() == "Windows":
    # `daemon` is Unix-only (run_erl); mix release on Windows ships
    # `bin\simulator.bat start`. Windows has no tty / pipe-buffer /
    # QoS-inheritance issues that motivated daemon mode on macOS,
    # so plain start is correct. open_console=false keeps the cmd
    # window hidden behind the game.
    return OS.create_process(binary, ["start"], false)
  # File descriptor limit: GUI children inherit ~256 fds; BEAM's
  # scheduler + ETS + connection pool can brush that under load.
  # Raise to 65536 before exec. `ulimit -n` is shell-builtin, no
  # external dependency, safe to run — failures don't block the
  # rest because we use `;` not `&&`.
  #
  # We also cd to release_root and redirect stdout/stderr to /dev/null
  # so the OS pipe buffer can't fill up and block a BEAM write.
  #
  # Previously tried wrapping with `taskpolicy -c user-interactive`
  # for QoS-promotion, but taskpolicy -c is demote-only on macOS
  # (utility/background/maintenance) so that invocation failed and
  # broke spawn entirely. Needs posix_spawn QoS attrs to actually
  # raise priority — not reachable from Godot's OS.create_process.
  # Parking that until we have a clean path.
  var release_root := binary.get_base_dir().get_base_dir()
  # `daemon` mode uses run_erl to detach from the controlling tty and
  # writes logs + pid file into $RELEASE_TMP. It's the supported shape
  # for non-terminal parents — our previous `start` attached the BEAM
  # to sh's stdin/tty and led to lifecycle + scheduling weirdness on
  # packaged .app launches.
  #
  # Capture stderr to a log file (not /dev/null) — if run_erl can't
  # start for any reason, we'd otherwise have no signal at all.
  var stderr_log := OS.get_environment("RELEASE_TMP").path_join(
    "spawn_stderr.log"
  )
  var script := (
    "ulimit -n 65536; cd %s && exec %s daemon >/dev/null 2>%s"
    % [_sh_quote(release_root), _sh_quote(binary), _sh_quote(stderr_log)]
  )
  print("[ServerManager] /bin/sh -c '%s'" % script)
  return OS.create_process("/bin/sh", ["-c", script])


func _sh_quote(s: String) -> String:
  # POSIX single-quote escaping: single-quote everything, handle
  # internal single quotes by closing, escaping, reopening.
  return "'" + s.replace("'", "'\\''") + "'"


func _ensure_path_has_standard_dirs() -> void:
  var current := OS.get_environment("PATH")
  var wanted := ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
  if OS.get_name() == "macOS":
    wanted.append("/usr/local/bin")
    wanted.append("/opt/homebrew/bin")
  var parts := current.split(":") if current != "" else PackedStringArray()
  var changed := false
  for dir in wanted:
    if not parts.has(dir):
      parts.append(dir)
      changed = true
  if changed:
    var new_path := ":".join(parts)
    OS.set_environment("PATH", new_path)
    print("[ServerManager] PATH augmented: %s" % new_path)


func _try_port_file_read() -> void:
  if _state != State.WAITING_PORT:
    return
  if FileAccess.file_exists(_port_file_path):
    var f := FileAccess.open(_port_file_path, FileAccess.READ)
    if f != null:
      var text: String = f.get_as_text().strip_edges()
      var parsed_port: int = text.to_int()
      if parsed_port > 0:
        _port = parsed_port
        print(
          "[ServerManager] read port from %s: %d"
          % [_port_file_path, _port]
        )
        # run_erl has written its pid file by now — swap our
        # sh-wrapper pid (which exited seconds ago) for the daemon's
        # real pid so the crash watchdog + stop() target correctly.
        _read_daemon_pid_into_self()
        _state = State.POLLING_READY
        _try_ready_probe()
        return
  if _now() >= _ready_deadline:
    _dump_release_tmp_postmortem()
    _fail_start("timed out waiting for port.txt")
    return
  get_tree().create_timer(READY_POLL_INTERVAL).timeout.connect(
    _try_port_file_read, CONNECT_ONE_SHOT
  )


func _dump_release_tmp_postmortem() -> void:
  # Port.txt timed out — dump every breadcrumb we have so we can
  # reconstruct why from logs alone (no access to the packaged .app's
  # stdout mid-run).
  var tmp := OS.get_environment("RELEASE_TMP")
  print("[ServerManager] postmortem: RELEASE_TMP=%s" % tmp)
  # Port-file-specific check, surfaced up-front. "port.txt missing"
  # vs "port.txt exists but we timed out waiting for it" are two
  # very different bugs (slow boot vs path-mismatch / race).
  if FileAccess.file_exists(_port_file_path):
    var mtime: int = FileAccess.get_modified_time(_port_file_path)
    var age: int = int(_now()) - mtime
    print(
      "[ServerManager] postmortem: port.txt EXISTS at %s "
      + "(mtime=%d, %d s ago) — polled but never picked up, race or "
      + "path mismatch" % [_port_file_path, mtime, age]
    )
  else:
    print(
      "[ServerManager] postmortem: port.txt MISSING at %s"
      % _port_file_path
    )
  # Dump the saves dir so we can see if port.txt landed somewhere
  # else (wrong DATABASE_PATH, different Godot user_data_dir).
  print("[ServerManager] postmortem: saves_dir=%s" % saves_dir())
  _dump_dir_tree(saves_dir(), 0)
  var stderr_log: String = tmp.path_join("spawn_stderr.log")
  if FileAccess.file_exists(stderr_log):
    var f := FileAccess.open(stderr_log, FileAccess.READ)
    if f != null:
      var contents := f.get_as_text()
      print(
        "[ServerManager] postmortem: spawn_stderr.log (%d bytes):\n%s"
        % [contents.length(), contents]
      )
  else:
    print("[ServerManager] postmortem: spawn_stderr.log missing")
  # Also flag whether the sh-wrapper pid has already exited — that
  # tells us whether BEAM forked at all.
  if _pid > 0:
    var alive: bool = _pid_alive(_pid)
    print(
      "[ServerManager] postmortem: sh-wrapper pid=%d alive=%s"
      % [_pid, alive]
    )


func _dump_dir_tree(path: String, depth: int) -> void:
  if depth > 3:
    return
  var d := DirAccess.open(path)
  if d == null:
    print("[ServerManager] postmortem: can't open %s" % path)
    return
  d.list_dir_begin()
  while true:
    var n := d.get_next()
    if n == "":
      break
    var full := path.path_join(n)
    var indent := "  ".repeat(depth + 1)
    if d.current_is_dir():
      print("%s[dir ] %s" % [indent, full])
      _dump_dir_tree(full, depth + 1)
    else:
      var size: int = FileAccess.get_file_as_bytes(full).size()
      print("%s[file] %s (%d bytes)" % [indent, full, size])
      _maybe_dump_file_contents(full, size)
  d.list_dir_end()


func _maybe_dump_file_contents(full: String, size: int) -> void:
  # Only matters during postmortem: print the inside of anything
  # log-ish so `erlang.log.1` + `run_erl.log` actually reach the
  # Godot console instead of just being listed by name.
  var name := full.get_file()
  # run_erl pipe fds — reading would block or return garbage.
  if name.ends_with(".w") or name.ends_with(".r"):
    return
  if not name.contains(".log"):
    return
  var f := FileAccess.open(full, FileAccess.READ)
  if f == null:
    return
  const MAX_DUMP_BYTES := 16384
  var text: String
  if size <= MAX_DUMP_BYTES:
    text = f.get_as_text()
  else:
    # Tail of the file — error + traceback almost always land there.
    f.seek(size - MAX_DUMP_BYTES)
    text = (
      "[…truncated %d bytes, showing tail…]\n" % (size - MAX_DUMP_BYTES)
      + f.get_as_text()
    )
  print("---- %s ----\n%s\n----" % [full, text])


func _read_daemon_pid_into_self() -> void:
  if not FileAccess.file_exists(_pid_file_path):
    push_warning(
      "[ServerManager] daemon pid file missing at %s"
      % _pid_file_path
    )
    return
  var f := FileAccess.open(_pid_file_path, FileAccess.READ)
  if f == null:
    return
  var parsed: int = f.get_as_text().strip_edges().to_int()
  if parsed > 0:
    _pid = parsed
    print("[ServerManager] daemon pid=%d" % parsed)
    _reset_beam_background_qos(parsed)


func _reset_beam_background_qos(beam_pid: int) -> void:
  ## macOS only: an .app spawned from Finder/LaunchServices can
  ## propagate "background" scheduling policy to its children. On
  ## Apple Silicon that pins the BEAM's scheduler threads to E-cores
  ## and manifests as 800% CPU + stalled agents. `taskpolicy -B -p
  ## <pid>` clears the background flag on the running process — the
  ## man page restricts -B to -p (can't wrap a new program with it,
  ## only apply to existing pids). Harmless when nothing was set.
  if OS.get_name() != "macOS":
    return
  var out: Array = []
  var code := OS.execute(
    "/usr/sbin/taskpolicy",
    ["-B", "-p", str(beam_pid)],
    out, true
  )
  if code == 0:
    print("[ServerManager] taskpolicy -B -p %d → OK" % beam_pid)
  else:
    push_warning(
      "[ServerManager] taskpolicy -B failed code=%d out=%s"
      % [code, "".join(out)]
    )


func _resolve_server_binary() -> String:
  # Try each candidate in order; first one whose binary exists wins.
  # Log every candidate + outcome so packaged builds leave a trail.
  for base in _binary_candidates():
    var bin := _append_bin(base)
    var exists: bool = FileAccess.file_exists(bin)
    print(
      "[ServerManager] candidate %s → %s"
      % [bin, "FOUND" if exists else "missing"]
    )
    if exists:
      return bin
  return ""


func _binary_candidates() -> Array[String]:
  var out: Array[String] = []

  # 1. Explicit env override wins.
  var override := OS.get_environment("SPACESIM_SERVER_PATH")
  if override != "":
    out.append(override)

  var exe_dir := OS.get_executable_path().get_base_dir()

  # 2. Shipped next to the game binary (Windows / Linux layout, and
  #    macOS if export preset puts non-resource files in Contents/MacOS).
  out.append(exe_dir.path_join("simulator"))

  # 3. macOS .app bundle: non-resource files typically land next to
  #    the .pck at Contents/Resources/. exe_dir is Contents/MacOS,
  #    so ../Resources/simulator.
  if OS.get_name() == "macOS":
    out.append(exe_dir.path_join("..").path_join(
      "Resources").path_join("simulator"))

  # 4. In-project bundle (dev or editor run when the release has been
  #    dropped at res://simulator/ for export-filter testing).
  out.append(ProjectSettings.globalize_path("res://simulator"))

  # 5. Sibling Elixir project's prod mix release (default dev path).
  out.append(ProjectSettings.globalize_path(
    "res://../simulator/_build/prod/rel/simulator"))

  return out


func _append_bin(base: String) -> String:
  match OS.get_name():
    "Windows":
      return base.path_join("bin").path_join("simulator.bat")
    _:
      return base.path_join("bin").path_join("simulator")


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
