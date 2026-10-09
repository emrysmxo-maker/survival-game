#!/usr/bin/env bash
# Готовые задачи для Godot и Blender (локально и в GitHub Actions, workflow «Tools»).
#   bash tools/ci/task.sh <задача> [аргументы]
# Переменные для своих команд: $GODOT, $BPY (python с bpy), $REPO, $OUT (сюда класть результаты: картинки, логи).
# Задачи:
#   parsecheck                 — импорт ресурсов + разбор всех скриптов и шейдеров
#   import                     — импорт ресурсов Godot (после смены .glb/.png/.jpg)
#   treecheck [x,y]            — деревья: виды, треугольники, плотность у точки
#   mapcheck [локации]         — карта леса и построек → $OUT/map.png
#   scene <сайт1,сайт2|@x:y>   — расстановка построек → $OUT/scene/*.json + рендер сверху (Blender)
#   shaders                    — шейдеры на программном Vulkan, только лог ошибок
#   props [имена]               — пересобрать godot/assets/props/props.glb (дома, машины, места) + импорт
#   houses|cars|places [имена] — превью моделей в Blender → $OUT/*.png (без сборки в игру)
#   trees [породы]             — пересобрать деревья → godot/assets/models + kinds.json + импорт
#   treeshow <варианты> [human|game] — рендер готовых деревьев → $OUT/trees.png
#   shot <x:y[:cam[:yaw[:elev[:time]]]]/x:y...> [кадров] — снимки игры (программный Vulkan) → $OUT/shots/*.png
#   intro                      — заставка «как всё началось» → $OUT/intro/intro_NN.jpg (кадр каждые 2 с)
#   blender <файл.py из репо> [аргументы]  — любой свой скрипт Blender (bpy)
#   godot <файл.gd из репо> [аргументы]    — любой свой скрипт Godot (extends SceneTree), headless
set -eo pipefail
T=${TOOLS:-/tmp/claude-0}
export REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export GODOT=${GODOT:-$T/godot/Godot_v4.3-stable_linux.x86_64}
export BPY=${BPY:-$T/blender/v/bin/python}
export OUT=${OUT:-$T/out}
export HOUSE_TEX=${HOUSE_TEX:-$T/houses/tex_game} PROP_TEX=${PROP_TEX:-$T/props/tex}
mkdir -p "$OUT"
G() { timeout "${GT:-900}" "$GODOT" --headless --path "$REPO/godot" "$@"; }
imp() { G --import >/dev/null 2>&1 || true; }

task=${1:-parsecheck}; shift || true
case "$task" in
	parsecheck) imp; G -s res://scripts/parsecheck.gd 2>&1 | grep -v "^Godot Engine" ;;
	import) imp; echo "import ok" ;;
	treecheck) imp; G -s res://scripts/treecheck.gd -- "$@" 2>&1 ;;
	mapcheck) imp; G -s res://scripts/mapcheck.gd -- "$OUT/map.png" "$@" 2>&1 | tail -40 ;;
	scene)
		imp; mkdir -p "$OUT/scene"
		G -s res://scripts/scenedump.gd -- "$OUT/scene" "${1:-village}" 2>&1 | tail -20
		for j in "$OUT"/scene/*.json; do "$BPY" -I "$REPO/tools/props/scene_render.py" "$REPO/godot/assets/props/props.glb" "$j" "${j%.json}.png" ${ELEV:-50} 2>&1 | sed '/Draco/d' | tail -3; done ;;
	shaders)
		imp
		VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout 300 xvfb-run -a "$GODOT" --path "$REPO/godot" --rendering-driver vulkan \
			--rendering-method mobile --quit-after 40 res://main.tscn -- --updurl=http://127.0.0.1:1/ 2>&1 | grep -iE "error|shader|fail" | head -60 || true
		echo "shaders done" ;;
	props)
		mkdir -p "$T/props/all"
		ONLY="${1:-${ONLY:-}}" "$BPY" -I "$REPO/tools/props/build_all.py" "$T/props/all/props.glb" 2>&1 | sed '/Draco/d' | tail -30
		cp "$T/props/all/props.glb" "$REPO/godot/assets/props/props.glb"
		ls -la "$REPO/godot/assets/props/props.glb"; imp; echo "props ok (нужен новый APK: поднять godot/apk_min.txt)" ;;
	houses|cars|places)
		f=$REPO/tools/houses/house.py; [ "$task" = cars ] && f=$REPO/tools/cars/car.py; [ "$task" = places ] && f=$REPO/tools/houses/places.py
		ONLY="${1:-}" SHOW=1 "$BPY" -I "$f" "$OUT" 2>&1 | sed '/Draco/d' | tail -20; ls "$OUT"/*.png ;;
	trees)
		mkdir -p "$T/trees/game"
		ONLY="${1:-}" SHOW=0 "$BPY" -I "$REPO/tools/trees/treegen.py" "$T/trees/game" 2>&1 | sed '/Draco/d' | tail -30
		cp "$T"/trees/game/*_wood.glb "$T"/trees/game/*_leaf.glb "$REPO/godot/assets/models/"
		python3 - "$T/trees/game/kinds_trees.json" "$REPO/godot/assets/models/kinds.json" <<'PY'
import json, sys
new = json.load(open(sys.argv[1])); k = json.load(open(sys.argv[2])); k.update(new)
json.dump(k, open(sys.argv[2], "w"), ensure_ascii=False); print("kinds:", len(k))
PY
		imp; echo "trees ok (нужен новый APK: поднять godot/apk_min.txt)" ;;
	treeshow) "$BPY" -I "$REPO/tools/trees/show.py" "$REPO/godot/assets/models" "$OUT/trees.png" "$T/trees/dl" "$1" "${2:-human}" 2>&1 | tail -5 ;;
	shot)
		imp; mkdir -p "$OUT/shots"
		VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout "${GT:-1800}" xvfb-run -a -s "-screen 0 1600x720x24" "$GODOT" --path "$REPO/godot" \
			--rendering-driver vulkan --rendering-method mobile --resolution 1600x720 res://main.tscn -- --updurl=http://127.0.0.1:1/ \
			--shot="$OUT/shots" "--views=${1:-4:6}" --shots="${2:-1}" 2>&1 | grep -E "SHOT|DRAW|SCRIPT ERROR|Parse Error|ERROR: res:" || true
		ls "$OUT/shots" ;;
	intro)
		imp; rm -rf "$OUT/intro"; mkdir -p "$OUT/intro"
		VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout "${GT:-1800}" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$REPO/godot" \
			--rendering-driver vulkan --rendering-method mobile --resolution 1280x720 res://main.tscn -- --updurl=http://127.0.0.1:1/ \
			--intro --introshot="$OUT/intro" 2>&1 | grep -E "SCRIPT ERROR|ERROR: res:|Parse Error" || true
		ls "$OUT/intro" | wc -l ;;
	blender|godot)
		f=$(realpath -m "$REPO/$1"); shift
		case "$f" in "$REPO"/*) ;; *) echo "файл должен быть в репозитории"; exit 2 ;; esac
		[ -f "$f" ] || { echo "нет файла $f"; exit 2; }
		if [ "$task" = blender ]; then "$BPY" -I "$f" "$@" 2>&1 | sed '/Draco/d'
		else imp; rel=${f#"$REPO/godot/"}; G -s "res://$rel" -- "$@" 2>&1; fi ;;
	*) echo "нет задачи «$task»; см. начало tools/ci/task.sh"; exit 2 ;;
esac
