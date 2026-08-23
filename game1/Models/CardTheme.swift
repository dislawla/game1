// Models/CardTheme.swift
//
// Порт интерфейса CardTheme из src/lib/cardArt.ts.

import SwiftUI

struct CardTheme {
    let primary: Color
    let secondary: Color

    /// Цвета "на всякий случай", пока силуэт ещё не вырезан (порт дефолтов
    /// `{ primary: "#96dcff", secondary: "#78c8ff" }` из CardFrame.tsx).
    static let placeholder = CardTheme(
        primary: Color(red: 0x96 / 255, green: 0xdc / 255, blue: 0xff / 255),
        secondary: Color(red: 0x78 / 255, green: 0xc8 / 255, blue: 0xff / 255)
    )
}
