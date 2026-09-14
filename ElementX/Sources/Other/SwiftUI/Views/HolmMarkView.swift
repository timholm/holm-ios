//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

/// Holm's mark: a solid rounded square — the body — held inside a thin ring — the seal.
///
/// The same two pieces stand in for every object in the brand: a message, a seal,
/// a key, a network, a door. Here the seal draws itself closed around the body and
/// then breathes, so the mark reads as something live rather than a static badge.
struct HolmMarkView: View {
    /// Overall size of the mark.
    var size: CGFloat = 132
    /// Set to false for a still mark (previews, snapshot tests).
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sealProgress: CGFloat = 0
    @State private var bodyScale: CGFloat = 0.72
    @State private var bodyOpacity: CGFloat = 0
    @State private var breathe = false

    private let teal = Color(red: 0.180, green: 0.769, blue: 0.714)
    private let gold = Color(red: 0.878, green: 0.702, blue: 0.396)

    private var ringWidth: CGFloat { max(1.5, size * 0.018) }
    private var bodySize: CGFloat { size * 0.46 }

    var body: some View {
        ZStack {
            halo
            seal
            body_
        }
        .frame(width: size, height: size)
        .onAppear(perform: start)
        .accessibilityHidden(true)
    }

    /// A soft field of light behind the mark, so it sits in the dark rather than on it.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(colors: [teal.opacity(0.28), teal.opacity(0.06), .clear],
                               center: .center,
                               startRadius: 0,
                               endRadius: size * 0.62)
            )
            .scaleEffect(breathe ? 1.06 : 0.94)
            .opacity(breathe ? 1 : 0.78)
    }

    /// The seal: a thin ring that closes around the body.
    private var seal: some View {
        Circle()
            .trim(from: 0, to: sealProgress)
            .stroke(
                AngularGradient(colors: [gold.opacity(0.35), gold, teal, gold.opacity(0.35)],
                                center: .center),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: gold.opacity(0.35), radius: size * 0.06)
    }

    /// The body: the solid rounded square the whole system is built from.
    private var body_: some View {
        RoundedRectangle(cornerRadius: bodySize * 0.28, style: .continuous)
            .fill(
                LinearGradient(colors: [teal, teal.opacity(0.72)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
            .frame(width: bodySize, height: bodySize)
            .shadow(color: teal.opacity(0.45), radius: size * 0.09, y: size * 0.02)
            .scaleEffect(bodyScale)
            .opacity(bodyOpacity)
    }

    private func start() {
        guard animated, !reduceMotion else {
            sealProgress = 1
            bodyScale = 1
            bodyOpacity = 1
            return
        }

        withAnimation(.easeInOut(duration: 1.1)) { sealProgress = 1 }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.28)) {
            bodyScale = 1
            bodyOpacity = 1
        }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(1.1)) {
            breathe = true
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.035, green: 0.055, blue: 0.058).ignoresSafeArea()
        HolmMarkView()
    }
}
