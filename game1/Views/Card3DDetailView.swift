// Views/Card3DDetailView.swift
//
// Порт BeastCardModal3D.tsx: полноэкранный просмотр карточки с вращением через
// перетаскивание (DragGesture) и ледяной обводкой персонажа, усиливающейся с
// углом поворота. requestAnimationFrame-throttling из веб-версии здесь не нужен —
// SwiftUI-жесты и так синхронизированы с дисплей-линком нативно.

import SwiftUI

struct Card3DDetailView: View {
    let beast: Beast
    let onClose: () -> Void

    @State private var rotation: (x: Double, y: Double) = (0, 0)
    @State private var dragStartRotation: (x: Double, y: Double) = (0, 0)
    @State private var isDragging = false

    private var iceIntensity: Double {
        min(max((abs(rotation.x) + abs(rotation.y)) / 60, 0), 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { if !isDragging { onClose() } }

            CardFrameView(
                name: beast.name,
                power: beast.power,
                imageName: beast.imageName,
                hasFrame: beast.hasFrame,
                size: .large,
                tilt: rotation
            ) { art in
                iceOutline(art: art)
            }
            .frame(maxWidth: 420)
            .padding(32)
            .rotation3DEffect(.degrees(rotation.y), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(rotation.x), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .animation(isDragging ? nil : .easeOut(duration: 0.3), value: rotation.x)
            .animation(isDragging ? nil : .easeOut(duration: 0.3), value: rotation.y)
            .gesture(dragGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartRotation = rotation
                }
                // Порт формулы из handleMouseMove: инвертированный X, /10 на оба
                // угла, клампинг ±45°.
                let newY = dragStartRotation.y + (-value.translation.width) / 10
                let newX = dragStartRotation.x + value.translation.height / 10
                rotation = (x: min(max(newX, -45), 45), y: min(max(newY, -45), 45))
            }
            .onEnded { _ in
                isDragging = false
                rotation = (0, 0)
            }
    }

    @ViewBuilder
    private func iceOutline(art: ExtractedCardArt) -> some View {
        let opacity = 0.25 + iceIntensity * 0.65
        let blurSharp = 1 + iceIntensity * 2
        let blurSoft = 3 + iceIntensity * 7

        // В SwiftUI .shadow() считается по уже применённой прозрачности исходного
        // вью — opacity(0) до shadow погасил бы и саму тень. В веб-версии оверлей
        // тоже был видимым дублем силуэта с drop-shadow, а не invisible-триком,
        // так что здесь то же самое: слегка видимая копия картинки + свечение.
        Image(uiImage: art.silhouette)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .shadow(color: .white.opacity(opacity), radius: blurSharp)
            .shadow(color: art.theme.primary.opacity(opacity * 0.85), radius: blurSoft)
            .animation(isDragging ? nil : .easeOut(duration: 0.3), value: iceIntensity)
    }
}
