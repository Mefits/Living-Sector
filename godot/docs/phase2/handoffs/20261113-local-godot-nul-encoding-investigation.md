# P2 Windows local Godot 4.7.2: persistent Unexpected NUL characters

User screenshot after pulling parser fixes shows 4 identical `Unicode parsing error, some characters were replaced with U+FFFD: Unexpected NUL character` messages, **without file path**. Previously reported parser errors in N20/N30/N57/N68 are not shown in this latest screenshot. Do NOT assume four NUL messages correspond to those four corrected scripts.

Read-only portable Windows diagnostics delivered in source (without cloud CI):
- `godot/scripts/diagnose_text_encoding.ps1` enumerates Godot source text files (`.gd/.tscn/.tres/.cfg/.godot/.json/.shader`), ignoring generated `.godot` and `.git`; detects embedded 0x00, UTF-16 BOM, invalid UTF-8, U+FFFD; prints relative path and writes `%TEMP%/livingsector-godot-encoding-report.txt`; **does not modify game sources**.
- `godot/scripts/diagnose_text_encoding.cmd` double-click wrapper for nontechnical user. After GitHub Desktop Pull, with Godot closed, run `godot/scripts/diagnose_text_encoding.cmd`, share output containing `SUSPECT:` paths. Remote GitHub bytes for N20/N30/N57/N68 do not show NUL/replacement; cannot inspect user's filesystem remotely.
- If report finds zero suspect source files, generated Godot import cache may be stale. Stop Godot completely, **rename only the generated `godot/.godot` to `.godot-old`** and restart editor; NEVER delete `godot/project.godot`, `native/priv/galaxy/data` or Git `.git`.
- Nothing here proves every source script is clean or that Godot can now run; this is a local diagnosis step. **NO GITHUB ACTIONS** were launched. Next action depends on actual source path or fresh Godot line number.

Current integration estimate is about 30–35% `CODE_WIRED_UNVERIFIED`; not updated by the diagnostic helper.
