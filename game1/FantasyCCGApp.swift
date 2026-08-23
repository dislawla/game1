// FantasyCCGApp.swift
//
// Точка входа. v1 — только Коллекция + 3D-карточка (см. план в
// .claude/plans/melodic-scribbling-floyd.md), Lobby/Packs/Battle не переносились.

import SwiftUI

@main
struct FantasyCCGApp: App {
    var body: some Scene {
        WindowGroup {
            CollectionGridView()
                .preferredColorScheme(.dark)
        }
    }
}
