// CardArt/CardArtCache.swift
//
// Порт module-level Map-кэша из lib/cardArt.ts + хук useCardArt. actor вместо
// Map гарантирует, что при параллельных запросах (сетка из нескольких карточек
// сразу) вырезание одного и того же изображения не запустится дважды.

import Foundation

actor CardArtCache {
    static let shared = CardArtCache()

    private var tasks: [String: Task<ExtractedCardArt, Error>] = [:]

    private func key(_ imageName: String, _ hasFrame: Bool) -> String { "\(imageName)|\(hasFrame)" }

    func art(imageName: String, hasFrame: Bool) async throws -> ExtractedCardArt {
        let cacheKey = key(imageName, hasFrame)

        if let existing = tasks[cacheKey] {
            return try await existing.value
        }

        let task = Task<ExtractedCardArt, Error>.detached(priority: .userInitiated) {
            try CardArtExtractor.extract(imageName: imageName, hasFrame: hasFrame)
        }
        tasks[cacheKey] = task
        return try await task.value
    }
}
