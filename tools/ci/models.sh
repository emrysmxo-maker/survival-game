#!/usr/bin/env bash
# Отпечатки исходников моделей: если скрипты Blender менялись, а .glb в репозитории — нет, сборка APK пересоберёт модели сама.
#   bash tools/ci/models.sh check  — напечатать, что устарело: props и/или trees (пусто — всё свежее)
#   bash tools/ci/models.sh stamp  — записать отпечатки (делать после коммита свежих .glb)
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd); cd "$REPO"
hp() { cat $(ls tools/props/*.py tools/houses/*.py tools/cars/*.py | sort) | sha1sum | cut -c1-16; }
ht() { cat $(ls tools/trees/*.py | sort) | sha1sum | cut -c1-16; }
PF=godot/assets/props/props.src; TF=godot/assets/models/trees.src
case "${1:-check}" in
	check)
		[ "$(cat $PF 2>/dev/null)" = "$(hp)" ] || echo props
		[ "$(cat $TF 2>/dev/null)" = "$(ht)" ] || echo trees ;;
	stamp) hp > $PF; ht > $TF; echo "props $(cat $PF)  trees $(cat $TF)" ;;
esac
