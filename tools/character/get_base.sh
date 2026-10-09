#!/usr/bin/env bash
# Основа персонажа: «Human Base Meshes» от Blender Studio (CC0) → /tmp/claude-0/hbm (вне репозитория, ~50 МБ)
set -e
D=${HBM_DIR:-/tmp/claude-0/hbm}
[ -f "$D/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend" ] && { echo "уже есть: $D"; exit 0; }
mkdir -p "$D.dl" "$D"
curl -sSL -o "$D.dl/hbm.zip" "https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip"
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$D.dl/hbm.zip" "$D"
echo "готово: $D"
