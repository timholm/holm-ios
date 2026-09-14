//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// One entry in the row beside your chats — a space you belong to, or a site you saved.
enum HolmRailItem: Identifiable, Equatable {
    case space(SpaceServiceFilter)
    case link(HolmLink)

    var id: String {
        switch self {
        case .space(let space): space.id
        case .link(let link): link.id.uuidString
        }
    }

    var name: String {
        switch self {
        case .space(let space): space.room.name
        case .link(let link): link.title
        }
    }
}

/// Drag the row into the order you want. Spaces and saved sites sit in one list,
/// because they sit in one row.
struct HolmRailOrderSheet: View {
    let items: [HolmRailItem]
    let mediaProvider: MediaProviderProtocol?
    let onReorder: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ordered: [HolmRailItem] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(ordered) { item in
                    HStack(spacing: 16) {
                        icon(for: item)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())

                        Text(item.name)
                            .font(.compound.bodyLG)
                            .foregroundStyle(.compound.textPrimary)
                    }
                }
                .onMove { source, destination in
                    ordered.move(fromOffsets: source, toOffset: destination)
                    onReorder(ordered.map(\.id))
                }
                .listRowBackground(Color.compound.bgCanvasDefault)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .background(Color.compound.bgCanvasDefault)
            .navigationTitle("Rearrange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
            .onAppear { ordered = items }
        }
    }

    @ViewBuilder
    private func icon(for item: HolmRailItem) -> some View {
        switch item {
        case .space(let space):
            LoadableAvatarImage(url: space.room.avatarURL,
                                name: space.room.name,
                                contentID: space.room.id,
                                avatarSize: .room(on: .spaceFilters),
                                mediaProvider: mediaProvider)
        case .link(let link):
            if let icon = link.icon {
                Image(uiImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.compound.bgSubtlePrimary
                    .overlay {
                        Text(link.initial)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textSecondary)
                    }
            }
        }
    }
}
