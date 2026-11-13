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
# A nonempty file is not sufficient: reject Linux binaries and malformed packs.
# This is a cheap structural check, not a claim of successful Windows boot.
python3 - "$OUT/LivingSector.exe" "$OUT/LivingSector.pck" <<'PY'
import pathlib, struct, sys
exe, pck = (pathlib.Path(p) for p in sys.argv[1:])
with exe.open("rb") as f:
    dos = f.read(64)
    if len(dos) < 64 or dos[:2] != b"MZ":
        raise SystemExit("Export is not a Windows PE executable (MZ missing)")
    pe_offset = struct.unpack_from("<I", dos, 0x3c)[0]
    if pe_offset < 64 or pe_offset > exe.stat().st_size - 24:
        raise SystemExit("Invalid Windows PE header offset")
    f.seek(pe_offset)
    header = f.read(24)
    if header[:4] != bytes((80, 69, 0, 0)) or struct.unpack_from("<H", header, 4)[0] != 0x8664:
        raise SystemExit("Export is not a Windows x86_64 PE executable")
with pck.open("rb") as f:
    if f.read(4) != b"GDPC":
        raise SystemExit("Exported PCK has no Godot pack header")
print("WINDOWS_PE_X64_AND_GODOT_PCK_HEADERS_OK")
PY
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
