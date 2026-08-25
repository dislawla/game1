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

    // Все размеры ниже — доли ширины карточки (w), а не абсолютные точки.
    // Раньше 10pt текста или 24pt гема были одинаковы что на iPhone SE, что на
    // Pro Max — при разной ширине карточки в сетке (она считается от ширины
    // экрана) это давало то непропорционально крупные, то мелкие декорации.
    // Значения ниже подобраны так, чтобы (fraction * w) давало прежний вид
    // при исходных референсных ширинах (170pt — small, 320pt — large), а на
    // любой другой ширине масштабировалось вместе с карточкой.
    var cornerRadiusFraction: CGFloat { isLarge ? 0.05 : 0.0588 }
    var innerCornerInsetFraction: CGFloat { isLarge ? 0.0125 : 0.0235 }
    var artInsetTopBottom: (top: CGFloat, bottom: CGFloat) { isLarge ? (0.08, 0.26) : (0.06, 0.24) }
    var artInsetSides: CGFloat { isLarge ? 0.08 : 0.06 }
    var gemSizeFraction: CGFloat { isLarge ? 0.14375 : 0.1412 }
    var gemOffsetFraction: CGFloat { isLarge ? 0.04375 : 0.0471 }
    var nameFontSizeFraction: CGFloat { isLarge ? 0.0625 : 0.0588 }
    var namePaddingHFraction: CGFloat { isLarge ? 0.0625 : 0.0471 }
    var namePaddingVFraction: CGFloat { isLarge ? 0.01875 : 0.0059 }
    var nameStackSpacingFraction: CGFloat { isLarge ? 0.025 : 0.0235 }
    var powerSizeFraction: CGFloat { isLarge ? 0.175 : 0.1529 }
    var powerFontSizeFraction: CGFloat { isLarge ? 0.06875 : 0.0647 }
    var powerChipShadowFraction: CGFloat { isLarge ? 0.03125 : 0.0294 }
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
    /// Второй параметр — ширина карточки в поинтах, чтобы оверлей (например,
    /// ледяное свечение в Card3DDetailView) мог масштабировать свои эффекты
    /// относительно реального размера карточки, а не хардкодить pt.
    let overlay: (ExtractedCardArt, CGFloat) -> Overlay

    /// Явный init (не memberwise) — чтобы @ViewBuilder/@escaping точно применились
    /// к замыканию overlay без сомнений в поведении синтезированного инициализатора.
    init(
        name: String,
        power: Int,
        imageName: String,
        hasFrame: Bool = false,
        size: CardSize = .small,
        tilt: (x: Double, y: Double)? = nil,
        @ViewBuilder overlay: @escaping (ExtractedCardArt, CGFloat) -> Overlay
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
        // "Color.clear + aspectRatio" как якорь пропорций, GeometryReader — только
        // как .overlay поверх него. Раньше aspectRatio стоял НА самом GeometryReader,
        // и в LazyVGrid с адаптивными колонками "осиротевшая" карточка в последнем
        // неполном ряду (например, третья при 2 колонках) получала не то предложение
        // высоты и растягивалась — не 3:4, а произвольно. Через .overlay geometry
        // reader сам не участвует в определении итогового размера, только читает его.
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    cardContent(w: geo.size.width, h: geo.size.height)
                }
            )
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
    private func cardContent(w: CGFloat, h: CGFloat) -> some View {
        let cornerRadius = w * size.cornerRadiusFraction
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Стекло: настоящий системный блюр вместо CSS backdrop-filter. .regularMaterial
            // (не .ultraThinMaterial) — иначе на тёмном фоне карточка сливается в почти
            // невидимое пятно, границу видно не будет вообще.
            shape
                .fill(.regularMaterial)
            shape
                .fill(
                    LinearGradient(
                        colors: [theme.primary.opacity(0.32), Color(red: 0.043, green: 0.071, blue: 0.126), theme.secondary.opacity(0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.7)

            holoLayer(w: w, h: h)
                .clipShape(shape)

            Group {
                DiagonalStripes(angleDegrees: 118, spacing: w * 0.2706).stroke(Color.white.opacity(0.07), lineWidth: w * 0.0059)
                DiagonalStripes(angleDegrees: 24, spacing: w * 0.3765).stroke(Color.white.opacity(0.05), lineWidth: w * 0.0059)
            }
            .clipShape(shape)
            .blendMode(.overlay)

            RadialGradient(colors: [.clear, .white.opacity(0.05), .white.opacity(0.16)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: max(w, h) * 0.75)
                .blendMode(.screen)
                .clipShape(shape)

            shape
                .strokeBorder(Color.white.opacity(0.55), lineWidth: w * 0.0088)
            RoundedRectangle(cornerRadius: max(0, cornerRadius - w * size.innerCornerInsetFraction), style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: w * 0.0059)
                .padding(w * 0.07)

            artRegion(w: w, h: h)

            // Гем — верхний левый угол. VStack+HStack с двумя Spacer вместо
            // .position(): содержимое прижимается к углу, но никогда не может
            // "вылезти" за пределы (w×h), т.к. это обычная относительная раскладка.
            VStack {
                HStack {
                    gem(w: w)
                        .padding(w * size.gemOffsetFraction)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }

            // Имя + сила — прижаты к низу карточки тем же способом.
            VStack(spacing: w * size.nameStackSpacingFraction) {
                Spacer(minLength: 0)
                nameChip(w: w)
                    .frame(maxWidth: w * 0.84)
                powerChip(w: w)
            }
            .padding(.bottom, h * 0.03)
        }
        .frame(width: w, height: h)
        // Внешняя тень, чтобы карточка визуально "отрывалась" от тёмного фона
        // сетки, а не сливалась с ним. Радиус — доля w, иначе на крупной
        // (детальной) карточке тень выглядела бы непропорционально тонкой.
        .shadow(color: .black.opacity(0.5), radius: w * 0.0588, x: 0, y: h * 0.0265)
        .shadow(color: theme.primary.opacity(0.35), radius: w * 0.0824)
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
                let tiltShift = w * 0.0294
                return CGSize(width: tilt.y * tiltShift, height: tilt.x * tiltShift)
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

    /// Только содержимое гема, без позиционирования — куда его поставить решает
    /// cardContent() через alignment/Spacer (относительная раскладка). Сам гем
    /// (и его блик/тень) — доля переданной ширины карточки w.
    @ViewBuilder
    private func gem(w: CGFloat) -> some View {
        let gemSize = w * size.gemSizeFraction
        ZStack {
            GemShape()
                .fill(
                    LinearGradient(colors: [.white, theme.primary.opacity(0.9), theme.secondary.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            GemHighlightShape()
                .fill(Color.white.opacity(0.75))
                .blur(radius: gemSize * 0.0417)
                .frame(width: gemSize * 0.3, height: gemSize * 0.24)
                .offset(x: -gemSize * 0.2, y: -gemSize * 0.32)
        }
        .frame(width: gemSize, height: gemSize)
        .shadow(color: theme.primary.opacity(0.8), radius: gemSize * 0.25)
    }

    /// Область персонажа — раньше вырезалась .position() с вычисленными вручную
    /// центром/размером (абсолютные координаты, легко промахнуться и вылезти за
    /// карточку). Теперь просто relative-паддинг внутри уже готового (w×h) слоя —
    /// содержимое физически не может выйти за пределы родителя.
    @ViewBuilder
    private func artRegion(w: CGFloat, h: CGFloat) -> some View {
        let insetTB = size.artInsetTopBottom
        let insetSide = size.artInsetSides

        ZStack {
            if let art {
                Image(uiImage: art.silhouette)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                RoundedRectangle(cornerRadius: w * 0.047)
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.12), theme.primary.opacity(0.14), theme.secondary.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                    )
                    .blendMode(.overlay)
                overlay(art, w)
            }
        }
        .padding(.top, h * insetTB.top)
        .padding(.bottom, h * insetTB.bottom)
        .padding(.horizontal, w * insetSide)
    }

    @ViewBuilder
    private func nameChip(w: CGFloat) -> some View {
        Text(name.uppercased())
            .font(.system(size: w * size.nameFontSizeFraction, weight: .semibold))
            .foregroundStyle(Color(red: 0.918, green: 0.965, blue: 1))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, w * size.namePaddingHFraction)
            .padding(.vertical, w * size.namePaddingVFraction)
            .background(chipBackground(shape: Capsule(), borderWidth: w * 0.0059))
            .shadow(color: theme.primary.opacity(0.8), radius: w * 0.0353)
    }

    @ViewBuilder
    private func powerChip(w: CGFloat) -> some View {
        let powerSize = w * size.powerSizeFraction
        Text("\(power)")
            .font(.system(size: w * size.powerFontSizeFraction, weight: .bold))
            .foregroundStyle(Color(red: 0.918, green: 0.965, blue: 1))
            .frame(width: powerSize, height: powerSize)
            .background(chipBackground(shape: Circle(), borderWidth: w * 0.0059))
            .shadow(color: theme.primary.opacity(0.6), radius: w * size.powerChipShadowFraction)
    }

    @ViewBuilder
    private func chipBackground<S: InsettableShape>(shape: S, borderWidth: CGFloat) -> some View {
        shape
            .fill(LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.white.opacity(0.28), lineWidth: borderWidth))
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
        self.overlay = { _, _ in EmptyView() }
    }
}

// Живой предпросмотр в Xcode Canvas — сразу маленький (как в сетке) и крупный
// (как в детальном виде) вариант одной и той же карточки рядом.
#Preview("small") {
    CardFrameView(name: "JadeDragon", power: 5, imageName: "jadeDragonR", hasFrame: false, size: .small)
        .frame(width: 170, height: 170 * 4 / 3)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("large") {
    CardFrameView(name: "JadeDragon", power: 5, imageName: "jadeDragonR", hasFrame: false, size: .large)
        .frame(width: 320, height: 320 * 4 / 3)
        .padding()
        .preferredColorScheme(.dark)
}
