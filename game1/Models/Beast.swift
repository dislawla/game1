// Models/Beast.swift
//
// Порт src/api/api.ts (интерфейс Beast) из веб-версии.

import Foundation

struct Beast: Identifiable, Hashable {
    let id: String
    let name: String
    let power: Int
    /// Имя ассета в Assets.xcassets.
    let imageName: String
    /// false (по умолчанию) — imageName уже сам по себе персонаж на белом/прозрачном
    /// фоне, без рамки и текста. true — старая склеенная карточка (рамка + персонаж +
    /// текст в одном PNG), требует обрезки по FRAMED_ART_INSET перед вырезанием.
    let hasFrame: Bool

    init(id: String, name: String, power: Int, imageName: String, hasFrame: Bool = false) {
        self.id = id
        self.name = name
        self.power = power
        self.imageName = imageName
        self.hasFrame = hasFrame
    }
}
