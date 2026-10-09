#!/usr/bin/env bash
# Записи мокапа CMU Graphics Lab (http://mocap.cs.cmu.edu, свободно для любого использования) для анимаций героя
# → /tmp/claude-0/cmu_dl/data (вне репозитория). Какие записи — CLIPS в hero_mocap.py.
set -e
D=${CMU:-/tmp/claude-0/cmu_dl/data}
mkdir -p "$D"
for t in 77_18 113_15 111_09 143_30 80_25 79_90 139_03 07_01 07_04 09_01 143_18 79_37 13_33; do
	s=${t%_*}
	[ -s "$D/$s.asf" ] || curl -sSf -o "$D/$s.asf" "http://mocap.cs.cmu.edu/subjects/$s/$s.asf"
	[ -s "$D/$t.amc" ] || curl -sSf -o "$D/$t.amc" "http://mocap.cs.cmu.edu/subjects/$s/$t.amc"
done
echo "готово: $D"
