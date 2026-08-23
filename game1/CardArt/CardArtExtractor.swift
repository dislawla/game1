// CardArt/CardArtExtractor.swift
//
// Прямой порт src/lib/cardArt.ts: автоматически вырезает силуэт персонажа из
// изображения существа. Та же двухпутевая логика, что и в вебе:
//  1. Если у PNG уже есть настоящая альфа — используем её как есть, flood-fill
//     не запускается вообще.
//  2. Иначе — flood-fill фона от краёв области рисунка с защитой от "утечки"
//     на персонажа (тот же набор порогов, что был подобран вживую в веб-версии).
//
// Работает на raw RGBA8 (premultiplied) буфере через CoreGraphics, выполняется
// вне главного потока (см. CardArtCache/extract(imageName:hasFrame:)).

import UIKit
import CoreGraphics
import SwiftUI

enum CardArtExtractor {

    // Отступы области рисунка (в долях 0...1) — только для старых склеенных
    // карточек с рамкой (hasFrame == true). Порт FRAMED_ART_INSET.
    private static let framedInset = (top: 0.07, right: 0.07, bottom: 0.27, left: 0.07)

    // Те же пороги, что в lib/cardArt.ts — подбирались вживую на реальных
    // карточках (см. историю веб-версии), здесь переносятся без изменений.
    private static let seedThresholdSq: Double = 34 * 34
    private static let localThresholdSq: Double = 55 * 55
    private static let globalBoundSq: Double = 70 * 70
    private static let edgeStop: Double = 30
    private static let maxWorkWidth = 640

    /// Кроп + вырезание фона + сборка темы. Тяжёлая часть — вызывать только
    /// из фона (см. CardArtCache), не с главного потока.
    static func extract(imageName: String, hasFrame: Bool) throws -> ExtractedCardArt {
        guard let source = UIImage(named: imageName), let sourceCGImage = source.cgImage else {
            throw CardArtError.imageNotFound(imageName)
        }

        let srcW = sourceCGImage.width
        let srcH = sourceCGImage.height
        let scale = min(1.0, Double(maxWorkWidth) / Double(srcW))
        let fullW = max(1, Int((Double(srcW) * scale).rounded()))
        let fullH = max(1, Int((Double(srcH) * scale).rounded()))

        let inset = hasFrame ? framedInset : (top: 0.0, right: 0.0, bottom: 0.0, left: 0.0)
        let cropX = Int((Double(fullW) * inset.left).rounded())
        let cropY = Int((Double(fullH) * inset.top).rounded())
        let cropW = max(1, fullW - cropX - Int((Double(fullW) * inset.right).rounded()))
        let cropH = max(1, fullH - cropY - Int((Double(fullH) * inset.bottom).rounded()))

        // Шаг 1 — масштабируем исходник до рабочего размера (UIGraphicsImageRenderer
        // сам обеспечивает правильную, "как на экране", ориентацию сверху вниз).
        let fullRenderer = UIGraphicsImageRenderer(size: CGSize(width: fullW, height: fullH))
        let fullImage = fullRenderer.image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: fullW, height: fullH))
        }

        // Шаг 2 — вырезаем нужную область (аналог ctx.drawImage(full, cropX, cropY,
        // cropW, cropH, 0, 0, cropW, cropH) в JS: сдвигаем полное изображение так,
        // чтобы верхний левый угол crop-прямоугольника оказался в (0,0)).
        let cropRenderer = UIGraphicsImageRenderer(size: CGSize(width: cropW, height: cropH))
        let croppedImage = cropRenderer.image { _ in
            fullImage.draw(in: CGRect(x: -CGFloat(cropX), y: -CGFloat(cropY), width: CGFloat(fullW), height: CGFloat(fullH)))
        }
        guard let croppedCGImage = croppedImage.cgImage else { throw CardArtError.contextCreationFailed }

        // Шаг 3 — читаем raw RGBA8 (premultiplied, альфа последним байтом) буфер.
        // Важно: используем отдельно управляемый raw-буфер, а не `&swiftArray` —
        // указатель из `&array` гарантированно валиден только на время самого
        // вызова инициализатора, а CGContext держит его и использует позже при
        // .draw(); передавать туда `&pixels` было бы use-after-free.
        let byteCount = cropW * cropH * 4
        let rawBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        rawBuffer.initialize(repeating: 0, count: byteCount)
        defer { rawBuffer.deallocate() }

        guard let readContext = CGContext(
            data: rawBuffer,
            width: cropW,
            height: cropH,
            bitsPerComponent: 8,
            bytesPerRow: cropW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CardArtError.contextCreationFailed
        }
        readContext.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))

        // Копируем в обычный (безопасно управляемый ARC) массив — дальше работаем
        // только с ним, rawBuffer после этого не нужен.
        var pixels = [UInt8](UnsafeBufferPointer(start: rawBuffer, count: byteCount))

        // ---- Дальше — то же, что в extractCardArt() из lib/cardArt.ts ----

        func idxAt(_ x: Int, _ y: Int) -> Int { y * cropW + x }
        func byteAt(_ idx: Int) -> Int { idx * 4 }

        // Если исходник уже прозрачный — используем альфу как есть.
        let corner = max(0, min(6, min(cropW, cropH) / 2 - 1))
        func cornerAlpha(_ x: Int, _ y: Int) -> UInt8 { pixels[byteAt(idxAt(x, y)) + 3] }
        let hasRealAlpha = [
            cornerAlpha(corner, corner),
            cornerAlpha(cropW - 1 - corner, corner),
            cornerAlpha(corner, cropH - 1 - corner),
            cornerAlpha(cropW - 1 - corner, cropH - 1 - corner),
        ].contains { $0 < 250 }

        var finalAlpha = [UInt8](repeating: 255, count: cropW * cropH)

        if hasRealAlpha {
            for idx in 0..<finalAlpha.count {
                finalAlpha[idx] = pixels[byteAt(idx) + 3]
            }
        } else {
            // Фон почти всегда виден в углах области рисунка — усредняем 4 патча.
            func patchAverage(_ cx: Int, _ cy: Int, _ r: Int) -> (r: Double, g: Double, b: Double) {
                var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
                let x0 = max(0, cx - r), x1 = min(cropW - 1, cx + r)
                let y0 = max(0, cy - r), y1 = min(cropH - 1, cy + r)
                for y in y0...y1 {
                    for x in x0...x1 {
                        let i = byteAt(idxAt(x, y))
                        sr += Double(pixels[i]); sg += Double(pixels[i + 1]); sb += Double(pixels[i + 2])
                        n += 1
                    }
                }
                return (sr / n, sg / n, sb / n)
            }

            let corners = [
                patchAverage(corner, corner, corner),
                patchAverage(cropW - 1 - corner, corner, corner),
                patchAverage(corner, cropH - 1 - corner, corner),
                patchAverage(cropW - 1 - corner, cropH - 1 - corner, corner),
            ]
            let bg = (
                r: corners.map { $0.r }.reduce(0, +) / 4,
                g: corners.map { $0.g }.reduce(0, +) / 4,
                b: corners.map { $0.b }.reduce(0, +) / 4
            )

            // Карта резкости по яркости — большой перепад = реальная граница рисунка.
            var luminance = [Double](repeating: 0, count: cropW * cropH)
            for idx in 0..<luminance.count {
                let i = byteAt(idx)
                luminance[idx] = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
            }
            var gradient = [Double](repeating: 0, count: cropW * cropH)
            for y in 0..<cropH {
                for x in 0..<cropW {
                    let idx = idxAt(x, y)
                    let l = luminance[idx]
                    let right = x + 1 < cropW ? luminance[idx + 1] : l
                    let down = y + 1 < cropH ? luminance[idx + cropW] : l
                    gradient[idx] = abs(right - l) + abs(down - l)
                }
            }

            var alpha = [UInt8](repeating: 255, count: cropW * cropH)
            var visited = [Bool](repeating: false, count: cropW * cropH)
            var stack: [(Int, Int)] = []

            func seedIfBg(_ x: Int, _ y: Int) {
                guard x >= 0, y >= 0, x < cropW, y < cropH else { return }
                let idx = idxAt(x, y)
                if visited[idx] { return }
                if gradient[idx] > edgeStop { return }
                let i = byteAt(idx)
                let dr = Double(pixels[i]) - bg.r, dg = Double(pixels[i + 1]) - bg.g, db = Double(pixels[i + 2]) - bg.b
                if dr * dr + dg * dg + db * db <= seedThresholdSq {
                    visited[idx] = true
                    alpha[idx] = 0
                    stack.append((x, y))
                }
            }

            func spreadIfBg(_ x: Int, _ y: Int, _ fromIdx: Int) {
                guard x >= 0, y >= 0, x < cropW, y < cropH else { return }
                let idx = idxAt(x, y)
                if visited[idx] { return }
                if gradient[idx] > edgeStop { return }
                let i = byteAt(idx)
                let fromI = byteAt(fromIdx)
                let dr = Double(pixels[i]) - Double(pixels[fromI])
                let dg = Double(pixels[i + 1]) - Double(pixels[fromI + 1])
                let db = Double(pixels[i + 2]) - Double(pixels[fromI + 2])
                if dr * dr + dg * dg + db * db > localThresholdSq { return }
                let gr = Double(pixels[i]) - bg.r, gg = Double(pixels[i + 1]) - bg.g, gb = Double(pixels[i + 2]) - bg.b
                if gr * gr + gg * gg + gb * gb > globalBoundSq { return }
                visited[idx] = true
                alpha[idx] = 0
                stack.append((x, y))
            }

            for x in 0..<cropW { seedIfBg(x, 0); seedIfBg(x, cropH - 1) }
            for y in 0..<cropH { seedIfBg(0, y); seedIfBg(cropW - 1, y) }

            while let (x, y) = stack.popLast() {
                let fromIdx = idxAt(x, y)
                spreadIfBg(x + 1, y, fromIdx); spreadIfBg(x - 1, y, fromIdx)
                spreadIfBg(x, y + 1, fromIdx); spreadIfBg(x, y - 1, fromIdx)
            }

            // Лёгкое размытие альфы (радиус 1) — прячет "зубчатый" край flood-fill.
            finalAlpha = boxBlurAlpha(alpha, width: cropW, height: cropH, radius: 1)
        }

        // Записываем новую альфу обратно, пере-умножая RGB (буфер premultiplied) —
        // иначе на полупрозрачных краях после блюра появится светлый ореол.
        for idx in 0..<finalAlpha.count {
            let i = byteAt(idx)
            let newAlpha = finalAlpha[idx]
            let originalAlpha = pixels[i + 3]
            if newAlpha != originalAlpha {
                let ratio = originalAlpha == 0 ? 0.0 : Double(newAlpha) / Double(originalAlpha)
                pixels[i] = UInt8((Double(pixels[i]) * ratio).rounded().clamped(to: 0...255))
                pixels[i + 1] = UInt8((Double(pixels[i + 1]) * ratio).rounded().clamped(to: 0...255))
                pixels[i + 2] = UInt8((Double(pixels[i + 2]) * ratio).rounded().clamped(to: 0...255))
                pixels[i + 3] = newAlpha
            }
        }

        let theme = sampleThemeColors(pixels: pixels, width: cropW, height: cropH, alpha: finalAlpha)

        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let outputCGImage = CGImage(
                width: cropW,
                height: cropH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: cropW * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            throw CardArtError.pixelBufferUnavailable
        }

        return ExtractedCardArt(
            silhouette: UIImage(cgImage: outputCGImage),
            aspectRatio: CGFloat(cropW) / CGFloat(cropH),
            theme: theme
        )
    }

    /// Средний цвет непрозрачных (персонаж) пикселей отдельно для верха/низа —
    /// порт sampleThemeColors() из lib/cardArt.ts.
    private static func sampleThemeColors(pixels: [UInt8], width: Int, height: Int, alpha: [UInt8]) -> CardTheme {
        var topR = 0.0, topG = 0.0, topB = 0.0, topN = 0.0
        var botR = 0.0, botG = 0.0, botB = 0.0, botN = 0.0
        let mid = height / 2

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if alpha[idx] < 120 { continue }
                let i = idx * 4
                if y < mid {
                    topR += Double(pixels[i]); topG += Double(pixels[i + 1]); topB += Double(pixels[i + 2]); topN += 1
                } else {
                    botR += Double(pixels[i]); botG += Double(pixels[i + 1]); botB += Double(pixels[i + 2]); botN += 1
                }
            }
        }

        func boost(_ c: Double) -> Double { c + (255 - c) * 0.5 }
        func color(_ r: Double, _ g: Double, _ b: Double, _ n: Double, fallback: Color) -> Color {
            guard n > 0 else { return fallback }
            return Color(red: boost(r / n) / 255, green: boost(g / n) / 255, blue: boost(b / n) / 255)
        }

        return CardTheme(
            primary: color(topR, topG, topB, topN, fallback: CardTheme.placeholder.primary),
            secondary: color(botR, botG, botB, botN, fallback: CardTheme.placeholder.secondary)
        )
    }

    private static func boxBlurAlpha(_ alpha: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: alpha.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0, n = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                        sum += Int(alpha[ny * width + nx])
                        n += 1
                    }
                }
                out[y * width + x] = UInt8((Double(sum) / Double(n)).rounded())
            }
        }
        return out
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
