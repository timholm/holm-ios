//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// The spaces you belong to, kept out of the way until you ask for them. The mark in
/// the top corner slides this open — and is itself the way back to every message, so
/// the row holds nothing but spaces.
struct HomeScreenSpaceBar: View {
    let spaces: [SpaceServiceFilter]
    let selected: SpaceServiceFilter?
    let unreadSpaceIDs: Set<String>
    let mediaProvider: MediaProviderProtocol?
    let isExpanded: Bool
    let links: [HolmLink]
    let order: [String]
    let onSelect: (SpaceServiceFilter?) -> Void
    let onOpenLink: (HolmLink) -> Void
    let onChangePhoto: (HolmLink) -> Void
    let onRemoveLink: (HolmLink) -> Void
    let onRearrange: () -> Void
    let onCreateSpace: () -> Void
    let onAddBridge: () -> Void
    let onAddLink: () -> Void

    /// Spaces and saved sites in one row, in whatever order you dragged them into.
    private var orderedItems: [HolmRailItem] {
        let items = spaces.map(HolmRailItem.space) + links.map(HolmRailItem.link)
        guard !order.isEmpty else { return items }

        return items.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.id) ?? Int.max
            let right = order.firstIndex(of: rhs.id) ?? Int.max
            return left < right
        }
    }

    private let itemSize: CGFloat = 40
    private let openHeight: CGFloat = 70

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    Group {
                        switch item {
                        case .space(let space): spaceItem(space)
                        case .link(let link): linkItem(link)
                        }
                    }
                    .modifier(SlideOut(isExpanded: isExpanded, index: index))
                }

                createSpaceItem
                    .modifier(SlideOut(isExpanded: isExpanded, index: orderedItems.count))
            }
            .padding(.horizontal, 16)
            .frame(height: openHeight, alignment: .center)
        }
        .scrollDisabled(!isExpanded)
        .frame(height: isExpanded ? openHeight : 0)
        .clipped()
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isExpanded)
    }

    /// Something waiting in that space. A ring in the canvas colour keeps it legible
    /// against whatever the space's own icon happens to be.
    private func unreadDot(isShowing: Bool) -> some View {
        Circle()
            .fill(Color.compound.iconAccentPrimary)
            .frame(width: 11, height: 11)
            .overlay {
                Circle().strokeBorder(Color.compound.bgCanvasDefault, lineWidth: 2)
            }
            .offset(x: 2, y: -2)
            .scaleEffect(isShowing ? 1 : 0.1)
            .opacity(isShowing ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isShowing)
    }

    /// Room for one more. Dashed so it reads as an opening rather than another space.
    private var createSpaceItem: some View {
        Menu {
            Button { onCreateSpace() } label: {
                Label(L10n.actionCreateSpace, systemImage: "plus.circle")
            }
            Button { onAddBridge() } label: {
                Label("Add a bridge", systemImage: "arrow.triangle.2.circlepath")
            }
            Button { onAddLink() } label: {
                Label("Add a link", systemImage: "link")
            }
        } label: {
            Circle()
                .strokeBorder(Color.compound.borderInteractivePrimary,
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: itemSize, height: itemSize)
                .overlay {
                    CompoundIcon(\.plus, size: .small, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconSecondary)
                }
                .modifier(SpaceSelectionMarker(isSelected: false, width: itemSize))
        }
        .accessibilityLabel("Add a space or bridge")
    }

    /// A saved website, wearing its own favicon.
    private func linkItem(_ link: HolmLink) -> some View {
        Button {
            onOpenLink(link)
        } label: {
            Group {
                if let icon = link.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.compound.bgSubtlePrimary
                        .overlay {
                            Text(link.initial)
                                .font(.compound.bodyLGSemibold)
                                .foregroundStyle(.compound.textSecondary)
                        }
                }
            }
            .frame(width: itemSize, height: itemSize)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.compound.borderInteractiveSecondary, lineWidth: 1)
            }
            .modifier(SpaceSelectionMarker(isSelected: false, width: itemSize))
        }
        .accessibilityLabel(link.title)
        .contextMenu {
            Button { onChangePhoto(link) } label: {
                Label("Change photo", systemImage: "photo")
            }
            Button { onRearrange() } label: {
                Label("Rearrange", systemImage: "arrow.left.arrow.right")
            }
            Button(role: .destructive) { onRemoveLink(link) } label: {
                Label(L10n.actionRemove, systemImage: "trash")
            }
        }
    }

    private func spaceItem(_ space: SpaceServiceFilter) -> some View {
        let isSelected = selected?.id == space.id

        return Button {
            onSelect(isSelected ? nil : space)
        } label: {
            LoadableAvatarImage(url: space.room.avatarURL,
                                name: space.room.name,
                                contentID: space.room.id,
                                avatarSize: .room(on: .spaceFilters),
                                mediaProvider: mediaProvider)
                .clipShape(RoundedRectangle(cornerRadius: isSelected ? 12 : itemSize / 2,
                                            style: .continuous))
                .opacity(isSelected || selected == nil ? 1 : 0.55)
                .overlay(alignment: .topTrailing) {
                    unreadDot(isShowing: unreadSpaceIDs.contains(space.id))
                }
                .modifier(SpaceSelectionMarker(isSelected: isSelected, width: itemSize))
        }
        .accessibilityLabel(space.room.name)
        .contextMenu {
            Button { onRearrange() } label: {
                Label("Rearrange", systemImage: "arrow.left.arrow.right")
            }
        }
    }
}

/// Each item comes out of the corner in turn, so the row unfolds rather than appears.
private struct SlideOut: ViewModifier {
    let isExpanded: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.7, anchor: .leading)
            .offset(x: isExpanded ? 0 : -CGFloat(min(index + 1, 5)) * 10)
            // Keep the unfolding readable without making you wait for it: the stagger
            // stops compounding after a handful of spaces.
            .animation(.spring(response: 0.28, dampingFraction: 0.84)
                .delay(isExpanded ? min(Double(index), 5) * 0.016 : 0),
                value: isExpanded)
    }
}

/// The rule beneath the space you're looking at, and the corner easing that goes with it.
private struct SpaceSelectionMarker: ViewModifier {
    let isSelected: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        VStack(spacing: 7) {
            content
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isSelected)

            Capsule()
                .fill(Color.compound.iconAccentPrimary)
                .frame(width: isSelected ? width * 0.6 : 0, height: 3)
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isSelected)
        }
    }
}
