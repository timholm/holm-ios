//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// The chat list's search field. It rides at the top of the list rather than in the
/// navigation bar, so it scrolls away as you read and comes back when you pull down.
struct HolmSearchField: View {
    @Binding var query: String
    @Binding var isFocused: Bool

    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                CompoundIcon(\.search, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)

                TextField(text: $query) {
                    Text(L10n.actionSearch)
                        .foregroundStyle(.compound.textSecondary)
                }
                .focused($fieldIsFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.compound.textPrimary)
                .tint(.compound.iconAccentPrimary)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        CompoundIcon(\.close, size: .xSmall, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    .accessibilityLabel(L10n.actionClear)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.compound.bgSubtleSecondary,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            if fieldIsFocused {
                Button {
                    query = ""
                    fieldIsFocused = false
                } label: {
                    Text(L10n.actionCancel)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textActionAccent)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fieldIsFocused)
        .onChange(of: fieldIsFocused) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            guard newValue != fieldIsFocused else { return }
            fieldIsFocused = newValue
        }
    }
}
