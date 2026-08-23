// Data/BeastData.swift
//
// Порт массива `beasts` из src/api/api.ts. Имена ассетов должны совпадать
// с именами image set'ов в Assets.xcassets (без расширения .png).

import Foundation

enum BeastData {
    static let all: [Beast] = [
        Beast(id: "CoppyPuff", name: "CoppyPuff", power: 5, imageName: "CoppyPuffCommon", hasFrame: true),
        Beast(id: "Cringe", name: "Cringe", power: 5, imageName: "CringeCommon", hasFrame: true),
        Beast(id: "JadeDragon", name: "JadeDragon", power: 5, imageName: "jadeDragonR", hasFrame: false),
    ]
}
