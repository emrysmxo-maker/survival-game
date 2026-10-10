# Survival game — карта для Claude

Мобильная изометрическая выживалка (как Last Day on Earth). Владелец тестирует на RedMagic 10 Pro, присылает скриншоты/видео. Ответы — коротко, по-русски.

## Замысел игры
- **`docs/ДИЗАЙН.md`** — всё, о чём договорились с владельцем (персонаж-выживший, логика движения и стрельбы, главное меню и сложность, снаряжение, экран «Раскладка на брезенте», скины, источники моделей, порядок работы). Читать перед работой над этими темами; дополнять при новых договорённостях.

## Правила владельца
- После каждой правки: коммит в `main` + push + дать ссылку на APK. Если сессия настроена на ветку `ccr-…` — всё равно пушить в `main` (владелец разрешил; можно продублировать в ту ветку), не спрашивать. Обновлять `CHANGES_DRAFT.md` и `docs/КРАТКО.md` (≤3 КБ: состояние и следующие задачи — его читают другие ИИ, их коннектор плохо отдаёт большие файлы). Версию в `hud.gd` вручную НЕ менять — CI подставляет «сборка N · коммит» сам (то же написано в описании Release).
- Сначала замерить причину (лог/числа), потом чинить. Не гадать. Одна проблема за раз.
- «Пока обсуждаем / ничего не делай» — не запускать ничего.
- Инструменты: ТОЛЬКО Blender (bpy) и Godot. Снимки игры РАЗРЕШЕНЫ (владелец снял запрет): `bash tools/ci/task.sh shot x:y[:cam[:yaw[:elev[:time]]]]/...` — проверять вид снимками, числа — логом.
- Рабочий цикл: правка кода → проверка разбора (`godot --headless --path godot -s res://scripts/parsecheck.gd` — грузит все скрипты/шейдеры) → коммит+push → ссылка. Скриншоты/тесты на экране — только если меняется вид или владелец просит.
- Не тратить токены: не читать файлы целиком без нужды, не переделывать решённое.

## Текущее состояние (обновлять при каждом пуше, коротко)
- Последняя сборка: 115 (apk_min 112). 107–115 — детализация (картинка, износ `props.gdshader`, двери `doors.json`, фонари у генераторов, звук по месту, цвета моделей, осень, облака/тени, дым, листья). 106: главное меню «КАРАНТИН» (`menu.gd`, сохранение `user://save.cfg`). 103–105: живые облака при отдалении (`clouds.gd`), камера на 300 м, заставка при первом входе. Герой в кепке и фланели, заставка 3D-комикс (101). На телефоне облака 104 не проверены. Подробно и следующие шаги — конец `CHANGES_DRAFT.md` («НА ЧЁМ ОСТАНОВИЛИСЬ»).
- Бойца и зомби в игре нет (удалены в 64), вместо них свободная камера `main.focus` + `camctl.gd`. Старое (мокап 100STYLE, Swat, «уже решено» про бег/стрельбу) — `docs/СБОРКИ.md` и git.
- Запасной полный текст прежнего CLAUDE.md — `docs/запас/CLAUDE_полный.md`: НЕ читать и НЕ менять без прямой просьбы владельца.
- **История сборок 35–101** (пути, команды, причины решений) — `docs/СБОРКИ.md`. Читать нужную строку по поиску, а не целиком.
- Режим владельца: экономия токенов ВЫКЛЮЧЕНА (бонусные кредиты до 5 ноября); ответы короткие и по делу.

## Конвейеры (кратко; подробности — `docs/СБОРКИ.md`)
- Постройки/машины/места/сюжет → один `godot/assets/props/props.glb`: `tools/props/build_all.py` (+ `tools/houses/house.py|places.py|story.py`, `tools/cars/car.py`, текстуры `tools/props/tex.py`, фото-текстуры `tools/houses/get_tex.py`). glTF: `export_vertex_color='NAME'`. Расстановка — `scripts/props.gd` (улицы, дворы, локации, `put()` со следом; материалы → `shaders/props.gdshader` с износом/током в custom data 0..1; двери по `assets/props/doors.json`; ток от `generator_shed`), кэш на телефоне `user://props_cache.bin`. Цвет вершин в `house.py _paint` — sRGB (не srgb2lin!).
- Деревья: `tools/trees/treegen.py` (берёза/сосна/ель), `broadleaf.py` (осина, дуб, ольха, ива, яблоня, черёмуха), грибы `mushrooms.py`; LOD `_l1/_l2`, `kinds.json`.
- Герой: `tools/character/hero.py` → `assets/character/hero.glb` (основа Human Base Meshes CC0, `get_base.sh`), мокап CMU `cmu.py`/`hero_mocap.py`/`get_cmu.sh` → `hero_clips.json`; показ без игры `hero_show.py`. Заставка-комикс — `scripts/intro.gd` (снимки заставки ~8 мин — не запускать без просьбы, только parsecheck).
- Мир: `world_gen.gd` (лес массивами, хутора, дороги/асфальт, озёра, карьер, овраги, морок), `weather.gd`, `ambience.gd`, `crows.gd`, `clouds.gd` (облака при отдалении + тени облаков в ground.gdshader), `leaves.gd` (листья по ветру), `daynight.gd`.
- Проверки: `parsecheck.gd`, `overlapcheck.gd` (OVL/ROAD/FENCE = 0), `mapcheck.gd`, `treecheck.gd`, `task.sh shot` (DRAW — вызовы/треугольники), `task.sh shaders`.

## Карта (фундамент под миссии)
- `world_gen.gd`: `FEATURES`/`LANDMARKS` — 7 локаций, `HAMLETS` — 12 хуторов, `ROADS`/`TRACKS`, `LAKES`, `ZONES` (растительность), река `river_center_y`. Вода: `water_at()` + `shaders/water.gdshader`. Новую локацию/миссию — добавлять в `FEATURES` + `LANDMARKS`.
- Числа для потоков — в `WorldGen.init()` (`_lk/_ft/_zn`); словари из фоновых потоков не читать.

## Что где
- Старая браузерная игра (v7.5.1): `index.html`, `src/`, `sw.js` — НЕ трогать.
- Основная работа — порт на Godot 4.3 в `godot/` (Forward Mobile, ортокамера).
- `godot/scripts/`: `main.gd` (свободная камера: focus, cam_yaw/cam_elev/cam_size), `camctl.gd` (жесты пальцами, −/+), `world.gd` (чанки, MultiMesh деревьев, тени-эллипсоиды), `world_gen.gd` (рельеф, биомы, расстановка), `props.gd` (дома и машины), `daynight.gd`, `hud.gd`, `settings.gd`, `boot.gd`, `menu.gd` (главное меню).
- Модели: `godot/assets/models/*.glb` (Poly Haven CC0, 50 файлов) + `kinds.json` (вид → модель/узел/высота). Листва = `<имя>_leaf.glb` (шейдер `shaders/foliage.gdshader`), ствол/камни = `<имя>_wood.glb`.
- Инструменты: `tools/models/prep_models.py` (оригиналы → игровые glb: gltfpack + сокращение карточек листвы), `make_kinds.py`. Оригиналы моделей лежат вне репозитория (скачивать с Poly Haven).

## Как проверять без телефона
- Установка всего (Godot 4.3, Blender bpy 5.2.2, текстуры) в новом контейнере: `bash tools/ci/setup.sh` (~1 мин, повторно не качает).
- Задачи: `bash tools/ci/task.sh <задача>` — список в начале файла: parsecheck, shot, blender <файл.py>, godot <файл.gd>, props, trees, houses/cars/places (превью), scene, mapcheck, treecheck, shaders. Результаты — в `$OUT` (/tmp/claude-0/out).
- Снимок игры: `task.sh shot -43:-97:30/166:-133:12` → `$OUT/shots/shot_<точка>_<кадр>.jpg` (`scripts/shot.gd`: `--shot=папка --views=… --shots=N --every=с --wait=с`; ~40 с на точку на программном Vulkan, fps на снимках не настоящие). Вручную: `--updurl=http://127.0.0.1:1/` обязательно, иначе игра скачает code.pck с GitHub.
- То же на сервере GitHub: workflow «Tools» (`.github/workflows/tools.yml`, ручной запуск: task + args) → результат в ветке `tools-out`. Инструкция для других ИИ — `docs/ДЛЯ_ИИ.md`.
- Модели: если скрипты `tools/props|houses|cars|trees` изменены, а .glb не пересобраны, сборка APK пересоберёт их сама (`tools/ci/models.sh check`). После своей пересборки и коммита .glb — `bash tools/ci/models.sh stamp`.

## Сборка и выдача
Push в `main` → GitHub Actions собирает APK → Release `godot-latest`: https://github.com/emrysmxo-maker/survival-game/releases/download/godot-latest/survival-godot.apk (APK >100 МБ, в репозиторий не кладётся).

## Обновление по воздуху (тестовые сборки)
- Номер сборки = номер запуска workflow «Build Godot APK» (run_number), а не число в сообщении коммита. `apk_min` ставить по run_number (смотреть список запусков), иначе игра навсегда просит новый APK.
- APK при запуске показывает экран `boot.tscn` (`scripts/boot.gd`): сам проверяет `update.json` на Release `godot-latest`, докачивает `code.pck` (~0.3 МБ: скрипты/шейдеры/сцены) и подключает поверх APK, потом запускает игру. Кнопка «Проверить обновления» на экране и «⟳ Обновления» в настройках ⚙ в игре (там после обновления нужен перезапуск игры).
- CI собирает APK + пакет `Code` (preset в `export_presets.cfg`) и выкладывает `code.pck` + `update.json` (`build`, `size`, `apk_min`).
- Новый APK нужен, когда меняются: модели/текстуры (`assets/*.glb|jpg|png`), `project.godot`, `export_presets.cfg`, разрешения, новые `class_name`. Тогда поднять `godot/apk_min.txt` до номера сборки, в которой это выложено (иначе старый APK получит неполное обновление). Если игра у владельца старше `apk_min`, экран обновления просит скачать APK.
- Перед выходом в магазин ВЫКЛЮЧИТЬ: подгрузка исполняемого кода из интернета запрещена правилами магазинов.

## Ловушки среды
- `pkill -f`/`pgrep -f` с шаблоном из своей команды убивает свою оболочку; в Monitor — ждать по файлу-флагу.
- Длинные команды запускать `nohup … &`; `rm` с относительным glob после `cd` блокируется.
- Безопасность: `android/android.keystore` и пароль публичны — для магазина заменить секретным ключом.

## Blender (для своих моделей)
- Стоит как Python-модуль: `/tmp/claude-0/blender/v/bin/python -I скрипт.py` (внутри `import bpy`, экспорт `bpy.ops.export_scene.gltf`). Работает без экрана. Ворнинг про Draco игнорировать.
- Если контейнер новый: `cd /tmp/claude-0/blender && python3 -m venv v && v/bin/pip install bpy==5.2.2` (Python 3.13 — bpy 4.2 не ставится; 5.2.2 LTS проверен: импорт/экспорт glb работают).
