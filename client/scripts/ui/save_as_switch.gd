extends RefCounted
class_name SaveAsSwitch

## Shared flow for the pause menu + HUD save-as buttons.
##
## Sequence:
##   1. POST /api/admin/save-as {name}. The server flushes persistence
##      + runs VACUUM INTO (see simulator-rust http/admin.rs::save_as).
##   2. If the sim is an external (dev) server we can't restart,
##      surface a "saved, restart sim to play it" status and stop.
##   3. Otherwise ServerManager.switch_to() stops the current sim and
##      respawns it pointing at the new DB. When that finishes we hand
##      back to the caller to reload the scene.
##
## Callbacks:
##   `on_status.call(level: String, msg: String)` — progress + errors.
##      level is one of "info", "success", "warn", "danger" so each
##      caller can map to its own palette / toast style.
##   `on_switched.call()` — fires once the new sim is ready. Caller
##      reloads the main scene; we can't do it from here because we
##      don't own a Node.


static func perform(
  save_name: String,
  on_status: Callable,
  on_switched: Callable,
) -> void:
  var clean := save_name.strip_edges()
  if clean == "":
    on_status.call("warn", "Enter a save name.")
    return
  on_status.call("info", "Saving as '%s'…" % clean)
  NetworkManager.admin_save_as(
    clean,
    func(code: int, body: String) -> void:
      if not _is_ok(code):
        on_status.call("danger", _parse_error(body, code))
        return
      if ServerManager.is_using_existing_server():
        # Dev mode: shell owns the sim, we can't restart it.
        on_status.call(
          "success",
          "Saved as '%s' (restart sim to play it)" % clean,
        )
        return
      on_status.call("info", "Switching to '%s'…" % clean)
      ServerManager.switch_to(
        clean,
        func(status: int, msg: String) -> void:
          if status == OK:
            on_switched.call()
          else:
            on_status.call(
              "danger", "Switch failed: %s" % msg
            )
      )
  )


static func _is_ok(code: int) -> bool:
  return code == 200 or code == 201 or code == 204


static func _parse_error(body: String, code: int) -> String:
  var parsed: Variant = JSON.parse_string(body)
  if parsed is Dictionary and (parsed as Dictionary).has("error"):
    return "save-as: %s" % (parsed as Dictionary)["error"]
  return "save-as failed (%d)" % code
