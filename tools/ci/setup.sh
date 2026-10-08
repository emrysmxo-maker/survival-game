#!/usr/bin/env bash
# Ставит всё для работы с игрой без телефона: Godot 4.3 (headless), Blender (bpy 5.2.2), текстуры для моделей.
# Повторный запуск ничего не качает заново. Папка: $TOOLS (по умолчанию /tmp/claude-0).
#   bash tools/ci/setup.sh            — всё
#   SKIP_TEX=1 bash tools/ci/setup.sh — без текстур (хватает для проверки скриптов)
set -euo pipefail
TOOLS=${TOOLS:-/tmp/claude-0}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
GV=4.3
mkdir -p "$TOOLS/godot" "$TOOLS/blender"

# Godot
G="$TOOLS/godot/Godot_v${GV}-stable_linux.x86_64"
if [ ! -x "$G" ]; then
	echo "== Godot $GV"
	curl -sSL -o "$TOOLS/godot/g.zip" "https://github.com/godotengine/godot/releases/download/${GV}-stable/Godot_v${GV}-stable_linux.x86_64.zip"
	(cd "$TOOLS/godot" && unzip -qo g.zip && chmod +x "$G")
fi

# Blender как модуль Python (нужен Python 3.13)
PY=${PYTHON313:-$(command -v python3.13 || command -v python3)}
if [ ! -x "$TOOLS/blender/v/bin/python" ] || ! "$TOOLS/blender/v/bin/python" -c "import bpy, PIL, scipy" 2>/dev/null; then
	echo "== Blender (bpy 5.2.2) на $($PY --version)"
	"$PY" -m venv "$TOOLS/blender/v"
	"$TOOLS/blender/v/bin/pip" install -q bpy==5.2.2 pillow scipy
fi

if [ "${SKIP_TEX:-0}" != "1" ]; then
	BPY="$TOOLS/blender/v/bin/python"
	# процедурные текстуры старых построек
	mkdir -p "$TOOLS/props/tex"; [ -f "$TOOLS/props/tex/asphalt.jpg" ] || { echo "== tex.py"; "$BPY" -I "$REPO/tools/props/tex.py" "$TOOLS/props/tex"; }
	# фото-текстуры домов Poly Haven (CC0) + ужатые для игры
	echo "== текстуры домов"
	python3 "$REPO/tools/houses/get_tex.py" "$TOOLS/houses/tex" >/dev/null
	"$BPY" -I "$REPO/tools/ci/shrink_tex.py" "$TOOLS/houses/tex" "$TOOLS/houses/tex_game"
	# небо и земля для рендеров-превью (деревья, дома, машины)
	echo "== небо/земля для превью"
	python3 "$REPO/tools/ci/get_dl.py" "$TOOLS/trees/dl"
fi
echo "== готово: GODOT=$G  BPY=$TOOLS/blender/v/bin/python"
