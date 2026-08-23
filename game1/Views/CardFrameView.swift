// Views/CardFrameView.swift
//
// Порт CardFrame.tsx + CardFrame.module.css: карточка-блок льда/стекла с
// автоматически вырезанным силуэтом персонажа внутри. Персонаж и тема цвета
// берутся из CardArtCache (порт lib/cardArt.ts) — новую карточку добавляешь
// одной записью в BeastData, без Photoshop и ручной разметки слоёв.

import SwiftUI

enum CardSize {
    case small
    case large

    var isLarge: Bool { self == .large }
    var cornerRadius: CGFloat { isLarge ? 16 : 10 }
    var artInsetTopBottom: (top: CGFloat, bottom: CGFloat) { isLarge ? (0.08, 0.26) : (0.06, 0.24) }
    var artInsetSides: CGFloat { isLarge ? 0.08 : 0.06 }
    var gemSize: CGFloat { isLarge ? 46 : 24 }
    var gemOffset: CGFloat { isLarge ? 14 : 8 }
    var nameFontSize: CGFloat { isLarge ? 20 : 10 }
    var namePaddingH: CGFloat { isLarge ? 20 : 8 }
    var namePaddingV: CGFloat { isLarge ? 6 : 1 }
    var nameBottomFraction: CGFloat { isLarge ? 0.15 : 0.14 }
    var powerSize: CGFloat { isLarge ? 56 : 26 }
    var powerFontSize: CGFloat { isLarge ? 22 : 11 }
}

/// Диагональные полосы (порт .cracks — repeating-linear-gradient тонких линий).
private struct DiagonalStripes: Shape {
    let angleDegrees: Double
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let angle = angleDegrees * .pi / 180
        let dx = cos(angle), dy = sin(angle)
        let px = -dy, py = dx
        let diag = (rect.width * rect.width + rect.height * rect.height).squareRoot()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = Int(diag / spacing) + 2
        guard count > 0 else { return path }
        for i in -count...count {
            let offset = CGFloat(i) * spacing
            let cx = center.x + px * offset
            let cy = center.y + py * offset
            path.move(to: CGPoint(x: cx - dx * diag, y: cy - dy * diag))
            path.addLine(to: CGPoint(x: cx + dx * diag, y: cy + dy * diag))
        }
        return path
    }
}

/// Кристаллический гем (порт .gem — clip-path pentagon).
private struct GemShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addLine(to: p(1.0, 0.38))
        path.addLine(to: p(0.82, 1.0))
        path.addLine(to: p(0.18, 1.0))
        path.addLine(to: p(0, 0.38))
        path.closeSubpath()
        return path
    }
}

/// Блик на гране (порт .gemHighlight — clip-path triangle).
private struct GemHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CardFrameView<Overlay: View>: View {
    let name: String
    let power: Int
    let imageName: String
    let hasFrame: Bool
    let size: CardSize
    /// Текущий угол наклона (rotateX/rotateY в градусах). Если задан — голограмма
    /// следует за поворотом вместо автономной анимации по таймеру (порт tilt-пропа).
    let tilt: (x: Double, y: Double)?
    let overlay: (ExtractedCardArt) -> Overlay

    /// Явный init (не memberwise) — чтобы @ViewBuilder/@escaping точно применились
    /// к замыканию overlay без сомнений в поведении синтезированного инициализатора.
    init(
        name: String,
        power: Int,
        imageName: String,
        hasFrame: Bool = false,
        size: CardSize = .small,
        tilt: (x: Double, y: Double)? = nil,
        @ViewBuilder overlay: @escaping (ExtractedCardArt) -> Overlay
    ) {
        self.name = name
        self.power = power
        self.imageName = imageName
        self.hasFrame = hasFrame
        self.size = size
        self.tilt = tilt
        self.overlay = overlay
    }

    @State private var art: ExtractedCardArt?
    @State private var idleDrift = false

    private var theme: CardTheme { art?.theme ?? .placeholder }

    private var tiltIntensity: Double {
        guard let tilt else { return 0 }
        return min(max((abs(tilt.x) + abs(tilt.y)) / 90, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)

            ZStack {
                // Стекло: настоящий системный блюр вместо CSS backdrop-filter.
                shape
                    .fill(.ultraThinMaterial)
                shape
                    .fill(
                        LinearGradient(
                            colors: [theme.primary.opacity(0.22), Color(red: 0.043, green: 0.071, blue: 0.126), theme.secondary.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.85)

                holoLayer(w: w, h: h)
                    .clipShape(shape)

                Group {
                    DiagonalStripes(angleDegrees: 118, spacing: 46).stroke(Color.white.opacity(0.07), lineWidth: 1)
                    DiagonalStripes(angleDegrees: 24, spacing: 64).stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .clipShape(shape)
                .blendMode(.overlay)

                RadialGradient(colors: [.clear, .white.opacity(0.05), .white.opacity(0.16)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: max(w, h) * 0.75)
                    .blendMode(.screen)
                    .clipShape(shape)

                shape
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                RoundedRectangle(cornerRadius: max(0, size.cornerRadius - 4), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    .padding(w * 0.07)

                gem(w: w, h: h)

                artRegion(w: w, h: h)

                nameChip(w: w, h: h)
                powerChip(w: w, h: h)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .task(id: "\(imageName)|\(hasFrame)") {
            do {
                art = try await CardArtCache.shared.art(imageName: imageName, hasFrame: hasFrame)
            } catch {
                print("Не удалось выделить силуэт персонажа (\(imageName)): \(error)")
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                idleDrift = true
            }
        }
    }

    @ViewBuilder
    private func holoLayer(w: CGFloat, h: CGFloat) -> some View {
        let holoGradient = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(red: 1, green: 0.882, blue: 0.588).opacity(0.7), location: 0.16),
                .init(color: Color(red: 1, green: 0.667, blue: 0.863).opacity(0.7), location: 0.32),
                .init(color: Color(red: 0.706, green: 0.647, blue: 1).opacity(0.7), location: 0.48),
                .init(color: Color(red: 0.549, green: 0.824, blue: 1).opacity(0.7), location: 0.64),
                .init(color: Color(red: 0.588, green: 1, blue: 0.824).opacity(0.7), location: 0.80),
                .init(color: .clear, location: 1),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let offset: CGSize = {
            if let tilt {
                return CGSize(width: tilt.y * 5, height: tilt.x * 5)
            }
            return CGSize(width: idleDrift ? w * 0.15 : -w * 0.15, height: idleDrift ? h * 0.15 : -h * 0.15)
        }()
        let opacity = tilt != nil ? 0.4 + tiltIntensity * 0.4 : 0.7

        holoGradient
            .frame(width: w * 2.2, height: h * 2.2)
            .offset(offset)
            .opacity(opacity)
            .blendMode(.overlay)
            .animation(tilt != nil ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true), value: idleDrift)
    }

    @ViewBuilder
    private func gem(w: CGFloat, h: CGFloat) -> some View {
        let gemSize = size.gemSize
        ZStack {
            GemShape()
                .fill(
                    LinearGradient(colors: [.white, theme.primary.opacity(0.9), theme.secondary.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            GemHighlightShape()
                .fill(Color.white.opacity(0.75))
                .blur(radius: 1)
                .frame(width: gemSize * 0.3, height: gemSize * 0.24)
                .offset(x: -gemSize * 0.2, y: -gemSize * 0.32)
        }
        .frame(width: gemSize, height: gemSize)
        .shadow(color: theme.primary.opacity(0.8), radius: 6)
        .position(x: size.gemOffset + gemSize / 2, y: size.gemOffset + gemSize / 2)
    }

    @ViewBuilder
    private func artRegion(w: CGFloat, h: CGFloat) -> some View {
        let insetTB = size.artInsetTopBottom
        let insetSide = size.artInsetSides
        let frameWidth = w * (1 - insetSide * 2)
        let frameHeight = h * (1 - insetTB.top - insetTB.bottom)
        let centerX = w * (insetSide + (1 - insetSide * 2) / 2)
        let centerY = h * (insetTB.top + (1 - insetTB.top - insetTB.bottom) / 2)

        ZStack {
            if let art {
                Image(uiImage: art.silhouette)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.12), theme.primary.opacity(0.14), theme.secondary.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                    )
                    .blendMode(.overlay)
                overlay(art)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .position(x: centerX, y: centerY)
    }

    /// bottom: X% в CSS — расстояние от НИЖНЕГО края карточки до нижнего края чипа.
    /// Высота текста-чипа не фиксирована заранее, поэтому берём приблизительную
    /// высоту по шрифту + вертикальный паддинг (близко к реальной, этого достаточно
    /// для позиционирования — точную подгонку проще один раз сделать на устройстве).
    @ViewBuilder
    private func nameChip(w: CGFloat, h: CGFloat) -> some View {
        let chipHeight = size.nameFontSize + size.namePaddingV * 2 + 6
        Text(name.uppercased())
            .font(.system(size: size.nameFontSize, weight: .semibold))
            .foregroundStyle(Color(red: 0.918, green: 0.965, blue: 1))
            .lineLimit(1)
            .padding(.horizontal, size.namePaddingH)
            .padding(.vertical, size.namePaddingV)
            .background(chipBackground(shape: Capsule()))
            .shadow(color: theme.primary.opacity(0.8), radius: 6)
            .frame(maxWidth: w * 0.84)
            .position(x: w / 2, y: h * (1 - size.nameBottomFraction) - chipHeight / 2)
    }

    @ViewBuilder
    private func powerChip(w: CGFloat, h: CGFloat) -> some View {
        Text("\(power)")
            .font(.system(size: size.powerFontSize, weight: .bold))
            .foregroundStyle(Color(red: 0.918, green: 0.965, blue: 1))
            .frame(width: size.powerSize, height: size.powerSize)
            .background(chipBackground(shape: Circle()))
            .shadow(color: theme.primary.opacity(0.6), radius: size.isLarge ? 10 : 5)
            .position(x: w / 2, y: h * 0.97 - size.powerSize / 2)
    }

    @ViewBuilder
    private func chipBackground<S: InsettableShape>(shape: S) -> some View {
        shape
            .fill(LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
    }
}

extension CardFrameView where Overlay == EmptyView {
    init(name: String, power: Int, imageName: String, hasFrame: Bool = false, size: CardSize = .small, tilt: (x: Double, y: Double)? = nil) {
        self.name = name
        self.power = power
        self.imageName = imageName
        self.hasFrame = hasFrame
        self.size = size
        self.tilt = tilt
        self.overlay = { _ in EmptyView() }
    }
}
