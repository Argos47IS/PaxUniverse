# Pax Interface 0.3.1

Настраиваемый интерфейс для Pax Universe 0.14.1: графитовые панели, линейные значки, читаемые команды, подсветка и плавный отклик кнопок, мягкие звуки наведения и нажатия.

Шапка собрана в одну строку: разделы игры, шесть шкал общества, дата и управление временем. Внизу — общий блок команд со счётчиками, карта и масштабирование. Справа открывается компактная карточка региона или панель оформления; они не перекрывают друг друга. Кнопки имеют градиент, фаски, мягкую подсветку и отклик на нажатие. Мод сохраняет штатную логику игровых команд и окон.

В версии 0.3.0 поддержаны роли игры 0.14.1: **страна, человек и организация**. HUD использует актуальные названия и окна игры: **Держава / Досье / Организация**, **Законы / Принципы / Устав**, **Добыча / Дела**. Новое окно «Работа и бизнес» получает общую тему и анимации; подписи и значки в настройке порядка команд тоже учитывают роль.

В версии 0.3.1 загрузка компонентов переведена на `PaxMod.load_resource()` для обновлённой песочницы модов. Тестовые сценарии вынесены из устанавливаемого мода в `tests/pax_interface/` репозитория; мод больше не обращается к аргументам запуска и не запускает диагностику самостоятельно. Настройки `appearance` и оформление сохранены.

## Установка

1. Закройте игру.
2. Положите `pax_interface-0.3.1.zip` в папку `mods` рядом с `PaxUniverse.exe`. Распаковывать ZIP не нужно.
3. Откройте лаунчер и проверьте, что **Pax Interface** включён в списке модов. При изменении списка перезапустите игру.
4. Загрузите партию или начните новую. Нажмите **«Интерфейс»** в нижней части экрана.

При обновлении заменяйте прежний ZIP этого мода, чтобы в `mods` оставалась одна версия `pax_interface`.

«Земля: Атлас HD» устанавливается отдельно. Pax Interface работает и без него; если установлен мод с ID `earth_atlas`, интерфейс загружается после него. Это порядок загрузки, а не обязательная зависимость.

## Настройка оформления

Изменения сразу видны в предпросмотре:

| Настройка | Возможности |
|---|---|
| Тема | Графит, Полночь, Сланец |
| Цвет акцента | Готовые цвета и произвольный цвет через палитру |
| Прозрачность панелей | 0–50%, то есть непрозрачность фона 100–50%; текст и значки остаются читаемыми |
| Масштаб интерфейса | 80–125% |
| Размер текста | Малый — 12, обычный — 14, крупный — 16; размеры остальных подписей меняются пропорционально |
| Подписи кнопок | Показать или скрыть названия основных команд; подсказки остаются доступны |
| Плавные переходы | Включить или отключить анимации оформления |
| Звуки интерфейса | Включение, отдельная громкость 0–100% и кнопка прослушивания |

Анимации, звук и громкость находятся в раскрываемом разделе «Отклик». Наведение звучит тише нажатия. Повторные звуки ограничены по частоте; ползунки не воспроизводят щелчки на каждом шаге. Подберите громкость через **«Прослушать звук»** вместе с обычной музыкой игры: комфортный уровень зависит от наушников, колонок и личных предпочтений.

## Перестановка команд

Включите **«Режим перестановки»** в панели настройки. Менять местами можно шесть основных позиций команд. Названия и значки зависят от роли: например, «Законы» становятся «Принципами» или «Уставом», а «Добыча» — «Делами». Недоступные в текущем режиме команды скрываются; сохранённый порядок остаётся общим.

- В сетке 2×3 в настройках перетаскивайте команду за ручку слева. Кнопки со стрелками позволяют передвигать её по одной позиции, в том числе с клавиатуры.
- На нижней панели можно перетаскивать основные кнопки друг на друга. В этом режиме нажатие не выполняет игровую команду.
- Нажмите **«Готово»**, чтобы закончить перестановку, затем **«Применить»**, чтобы сохранить результат. Выключить режим также можно переключателем в настройках.

Пауза и кнопка настройки доступны во время перестановки.

## Применение и отмена

- **«Применить»** сохраняет все текущие параметры и закрывает панель.
- **«Отмена»**, крестик закрытия или закрытие панели штатным управлением возвращают оформление, которое было при её открытии.
- **«Сбросить»** показывает стандартное оформление в предпросмотре. Чтобы сохранить сброс, нажмите **«Применить»**; **«Отмена»** возвращает прежние настройки.
- **«Готово»** завершает только режим перестановки; оно не заменяет **«Применить»**.

Настройки общие для партий и сохраняются отдельно от файлов мира: `user://mod_settings/pax_interface.json`, объект `appearance`. В стандартном профиле Windows этой установки это `%APPDATA%/Pax Universe/mod_settings/pax_interface.json`.

Есть русский и английский переводы; язык берётся из игры. Мод не меняет сохранения и не заменяет файлы PCK. Для отключения используйте список модов в лаунчере и перезапустите игру.

## Совместимость

Этот выпуск предназначен для **Pax Universe 0.15.1**. Значение `game_version` в манифесте учитывает устаревшую внутреннюю версию загрузчика игры — 0.13.2; оно не означает поддержку старых игр без нового `load_resource`. Основной HUD масштабируется, а игровые диалоги продолжают использовать собственную логику и ограничения размера. Мод адаптирует внутренние узлы `Main`, поэтому после обновления игры требуется проверка совместимости, даже если лаунчер допускает загрузку.

Для разработчиков: оригинальные кнопки и их обработчики сохраняются; новые основные кнопки передают им команды. При выгрузке адаптер восстанавливает изменённые свойства и расположение штатных узлов. Встроенные системные меню и отдельные составные элементы Godot сохраняют собственное поведение; единая анимация мода не подменяет все внутренние переходы `PopupMenu` и вкладок.

## English

**Pax Interface 0.3.1** is a customizable interface for **Pax Universe 0.15.1**. It adds graphite panels, clear command icons, hover feedback, transitions and gentle interface sounds while keeping native game commands and window logic. The manifest accommodates the game's stale internal loader version (0.13.2); older games without the new resource API are not supported by this release.

Version 0.3.0 supports country, person and organization roles, including Dossier, Principles, Charter and the new Work and Business window. Native command names, icons, targets and availability stay synchronized with the game and the reorder panel.

Version 0.3.1 loads its components through `PaxMod.load_resource()` for the updated mod sandbox. Development tests live in the repository's `tests/pax_interface/` directory, outside the installable mod. The mod no longer reads launch arguments or starts diagnostics itself. Existing appearance preferences are preserved.

Close the game, place `pax_interface-0.3.1.zip` in the `mods` folder beside `PaxUniverse.exe`, and leave the ZIP packed. Enable **Pax Interface** in the launcher, restart the game, then open **Interface** near the bottom of the screen. Keep only one installed version of this mod. **Earth Atlas HD** is optional; `load_after: earth_atlas` sets order only.

Choose Graphite, Midnight or Slate, set a custom accent, panel transparency from 0–50% (50–100% opacity), HUD scale from 80–125%, text size 12/14/16, command labels, motion and sound volume. Use **Preview sound** to choose a comfortable volume with your usual game audio.

Enable **Reorder mode** to drag command rows by their left handle, use their arrow buttons, or drag the six main dock buttons. **Done** ends reordering. **Apply** saves the preview; **Cancel** or closing the panel restores the previous appearance. **Reset** previews defaults and still needs **Apply** to save.

Preferences are stored separately from saves in `user://mod_settings/pax_interface.json`, under `appearance`. Russian and English follow the game language. The mod does not replace PCK files or change saved worlds. Its adapter uses internal `Main` nodes, so game updates require another compatibility check. Native dialogs retain their own logic and size constraints.
