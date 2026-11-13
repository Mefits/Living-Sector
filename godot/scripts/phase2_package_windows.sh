#!/usr/bin/env bash
# Living Sector P2 Windows x86_64 export: no network, no Actions, no fake success.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/godot"
OUT="$ROOT/build/windows"
ARCHIVE="$ROOT/build/LivingSector-P2-Windows-x64.zip"
GODOT_BIN="${GODOT_BIN:-godot}"
command -v "$GODOT_BIN" >/dev/null || { echo "Godot executable missing: $GODOT_BIN" >&2; exit 2; }
command -v zip >/dev/null || { echo "zip utility missing" >&2; exit 2; }
[[ -f "$PROJECT/project.godot" && -f "$PROJECT/export_presets.cfg" ]] || { echo "Godot project/preset missing" >&2; exit 2; }
mkdir -p "$OUT"
rm -f "$OUT/LivingSector.exe" "$OUT/LivingSector.pck" "$ARCHIVE"
echo "Exporting with $("$GODOT_BIN" --version) from $PROJECT"
# Export templates for the exact installed Godot version must already exist.
"$GODOT_BIN" --headless --path "$PROJECT" --export-release "Windows Desktop" "$OUT/LivingSector.exe"
[[ -s "$OUT/LivingSector.exe" ]] || { echo "Export produced no executable" >&2; exit 3; }
# With embed_pck=false a separate PCK must exist; never ship an EXE alone.
[[ -s "$OUT/LivingSector.pck" ]] || { echo "Export produced no PCK" >&2; exit 3; }
cat > "$OUT/README-RU.txt" <<'EOF'
Living Sector — Godot 4 P2 Windows x64
Распакуйте весь архив в одну папку и запустите LivingSector.exe.
LivingSector.pck должен находиться рядом с EXE.
Сохранения находятся в каталоге user://saves/ приложения Godot.
Эта сборка НЕ подтверждает полный паритет с Rust Galaxy 0.6.7.
Текущие ограничения и результаты проверок — в PR #249:
https://github.com/Mefits/Living-Sector/pull/249
EOF
(
 cd "$OUT"
 zip -q -9 "$ARCHIVE" LivingSector.exe LivingSector.pck README-RU.txt
)
unzip -t "$ARCHIVE" >/dev/null
echo "WINDOWS_ZIP_READY $ARCHIVE"
