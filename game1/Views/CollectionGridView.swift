// Views/CollectionGridView.swift
//
// Порт грид-части Collection.tsx. Тап по карточке открывает Card3DDetailView —
// на iOS это естественнее, чем имитация long-press таймером из веб-версии.

import SwiftUI

struct CollectionGridView: View {
    @State private var selectedBeast: Beast?

    private let columnCount = 2
    private let spacing: CGFloat = 16
    private let outerPadding: CGFloat = 16

    var body: some View {
        NavigationStack {
            // Размер карточки считаем явно, одним числом, от реальной доступной
            // ширины экрана — вместо того чтобы полагаться на то, как LazyVGrid
            // и внутренний GeometryReader/aspectRatio карточки договорятся между
            // собой (на практике это оказалось ненадёжно: карточка в неполном
            // ряду могла раздуться и наехать на соседние). Explicit .frame(width:
            // height:) на каждой карточке ниже гарантирует одинаковый размер
            // всегда, вне зависимости от того, сколько карточек и в каком ряду.
            GeometryReader { geo in
                let totalSpacing = spacing * CGFloat(columnCount - 1) + outerPadding * 2
                let cardWidth = (geo.size.width - totalSpacing) / CGFloat(columnCount)
                let cardHeight = cardWidth * 4 / 3
                let columns = Array(
                    repeating: GridItem(.fixed(cardWidth), spacing: spacing),
                    count: columnCount
                )

                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(BeastData.all) { beast in
                            Button {
                                selectedBeast = beast
                            } label: {
                                CardFrameView(
                                    name: beast.name,
                                    power: beast.power,
                                    imageName: beast.imageName,
                                    hasFrame: beast.hasFrame,
                                    size: .small
                                )
                                .frame(width: cardWidth, height: cardHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(outerPadding)
                }
            }
            .background(Color(red: 0.043, green: 0.075, blue: 0.098).ignoresSafeArea())
            .navigationTitle("Коллекция")
        }
        .fullScreenCover(item: $selectedBeast) { beast in
            Card3DDetailView(beast: beast) { selectedBeast = nil }
        }
    }
}

// Живой предпросмотр в Xcode Canvas (Editor → Canvas, ⌥⌘Return) — правишь код
// слева, картинка справа обновляется сама, без запуска симулятора.
#Preview {
    CollectionGridView()
        .preferredColorScheme(.dark)
}
