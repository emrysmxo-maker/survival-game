# Зомби: сборка модели

Модель — «Mobile Ready Zombie» (OpenGameArt, **CC0**, https://opengameart.org/content/mobile-ready-zombie).
Скелета и анимаций у неё нет, поэтому она привязана к скелету Mixamo бойца
(`assets/character/Soldier.glb`) — получает его клипы Walk/Idle/Run.

`rig_zombie.py` (Blender как Python-модуль: `pip install bpy`):
1. грузит Soldier.glb и Zombie.fbx (из архива Zombie.zip, папка `mob/`);
2. разворачивает зомби к скелету, масштабирует ×1.08, поднимает руки из A-позы в T-позу;
3. назначает текстуру Zombie.png (в FBX материал прозрачный);
4. привязывает к скелету с автоматическими весами, «запекает» обратную матрицу родителя;
5. удаляет меши бойца и экспортирует `Zombie.glb` с анимациями.

Результат — `assets/character/Zombie.glb`. Поведение, урон, конечности — `src/zombie.js`.
