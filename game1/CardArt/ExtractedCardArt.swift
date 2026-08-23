// CardArt/ExtractedCardArt.swift
//
// Порт интерфейса ExtractedCardArt из src/lib/cardArt.ts.

import UIKit

// @unchecked Sendable: значение пересекает границу актора (CardArtCache) через
// Task.detached — само по себе иммутабельно после создания, поэтому безопасно,
// но UIImage/Color в новых SDK не всегда автоматически размечены как Sendable.
struct ExtractedCardArt: @unchecked Sendable {
    /// Вырезанный силуэт персонажа с настоящей альфой (RGBA, premultiplied).
    let silhouette: UIImage
    /// Ширина/высота выреза, для точной подгонки контейнера под пропорции.
    let aspectRatio: CGFloat
    let theme: CardTheme
}

enum CardArtError: Error {
    case imageNotFound(String)
    case contextCreationFailed
    case pixelBufferUnavailable
}
