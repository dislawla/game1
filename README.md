# game1 — FantasyCCG (SwiftUI, v1)

Коллекция + 3D-карточка, перенесённые из веб-версии (репозиторий `TG-game/fantasy-ccg`).
Подробный контекст и порт-мэппинг веб→SwiftUI — в `.claude/plans/melodic-scribbling-floyd.md`
того репозитория; здесь только сам код.

Проект был создан в Xcode из шаблона **Game** (SpriteKit) — неиспользуемые файлы
(`AppDelegate.swift`, `SceneDelegate.swift`, `GameViewController.swift`,
`GameScene.*`, `Main.storyboard`) удалены, точка входа переведена на чистый
SwiftUI (`@main struct FantasyCCGApp: App` в `game1/FantasyCCGApp.swift`).

Этот код писался и переносился без доступа к Xcode — открой в Xcode, собери
(⌘B) и запусти (⌘R) на симуляторе. Если что-то не так — см. секцию "Известные
риски" в `.claude/plans/melodic-scribbling-floyd.md` исходного репозитория
(там разобраны самые вероятные места ошибок: вырезание силуэта через
CoreGraphics, подбор `perspective` для 3D-поворота, позиционирование текста).

## Структура

- `game1/Models/` — `Beast`, `CardTheme`
- `game1/Data/` — статические данные существ (`BeastData`)
- `game1/CardArt/` — автоматическое вырезание силуэта персонажа из карточки
  (порт `lib/cardArt.ts`)
- `game1/Views/` — `CardFrameView` (стеклянная/голографическая карточка),
  `CollectionGridView` (сетка), `Card3DDetailView` (полноэкранный 3D-просмотр)
- `game1/Assets.xcassets/` — 3 персонажа (`CoppyPuffCommon`, `CringeCommon`,
  `jadeDragonR`)
