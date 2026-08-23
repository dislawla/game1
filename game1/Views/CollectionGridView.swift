// Views/CollectionGridView.swift
//
// Порт грид-части Collection.tsx. Тап по карточке открывает Card3DDetailView —
// на iOS это естественнее, чем имитация long-press таймером из веб-версии.

import SwiftUI

struct CollectionGridView: View {
    @State private var selectedBeast: Beast?

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.043, green: 0.075, blue: 0.098).ignoresSafeArea())
            .navigationTitle("Коллекция")
        }
        .fullScreenCover(item: $selectedBeast) { beast in
            Card3DDetailView(beast: beast) { selectedBeast = nil }
        }
    }
}
