//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Defensive collection access beyond the existing `Collection[safe:]`.
///
/// `Other/Extensions/Collection.swift` already provides `subscript(safe:)`;
/// do not redeclare it here. These helpers cover the remaining crash-prone
/// patterns found in the audit:
///
/// - Slicing with a stale/out-of-bounds range traps. Clamp it first.
/// - Unconditional `removeFirst()` / `removeLast()` trap on empty
///   collections. Several vector-diff consumers apply `.popFront` / `.popBack`
///   updates from the SDK directly to arrays; a single out-of-order diff
///   would crash the app.
///
/// Timeline indexing audit (2026-09-30), all bounds-checked already:
/// - `Screens/Timeline/View/TimelineItemViews/GalleryGridView.swift:67` guards
///   `items.indices.contains(index)` before subscripting.
/// - `Screens/Timeline/View/Supplementary/TimelineReadReceiptsView.swift:67`
///   only indexes `0 ..< count` via `displayNumber`.
/// - `Services/Timeline/TimelineController/TimelineController.swift:488` uses
///   `enumerated()` + `indices.last`, no manual arithmetic.
/// - `Services/Search/SearchServiceProxy.swift:85-94`,
///   `Services/Spaces/SpaceRoomListProxy.swift:92-94`,
///   `Services/Spaces/SpaceServiceProxy.swift:149-184`,
///   `Services/Location/RoomLiveLocationService.swift:70-80` apply SDK
///   vector diffs (`popFront`/`popBack`/`insert`/`set`/`remove`/`truncate`)
///   with unconditional `removeFirst()`/`removeLast()`/subscripts. Correct as
///   long as the diff stream is well-formed; use the `*Safely` helpers below
///   if that trust ever needs relaxing.
nonisolated extension Collection {
    /// Returns `range` clamped to the collection's valid index range.
    ///
    /// Slicing a collection with an out-of-bounds range traps at runtime.
    /// Clamping first turns a stale range (e.g. from a pagination window
    /// computed before items were removed) into an empty slice instead of
    /// a crash.
    func clamped(_ range: Range<Index>) -> Range<Index> {
        let lowerBound = max(range.lowerBound, startIndex)
        let upperBound = min(range.upperBound, endIndex)
        guard lowerBound <= upperBound else {
            return endIndex..<endIndex
        }
        return lowerBound..<upperBound
    }
}

nonisolated extension BidirectionalCollection {
    /// Returns `index` moved into `indices`, or `nil` when the collection is empty.
    ///
    /// Use when an index was computed against an older snapshot of the
    /// collection (e.g. restoring a scroll position after the timeline
    /// changed underneath it).
    func clampedIndex(_ index: Index) -> Index? {
        guard !isEmpty else {
            return nil
        }
        if index < startIndex {
            return startIndex
        }
        if index < endIndex {
            return index
        }
        return self.index(before: endIndex)
    }
}

nonisolated extension RangeReplaceableCollection {
    /// Removes and returns the first element, or `nil` when empty.
    ///
    /// Drop-in safe replacement for unconditional `removeFirst()`, which
    /// traps on an empty collection.
    @discardableResult
    mutating func removeFirstSafely() -> Element? {
        isEmpty ? nil : removeFirst()
    }
}

nonisolated extension BidirectionalCollection where Self: RangeReplaceableCollection {
    /// Removes and returns the last element, or `nil` when empty.
    ///
    /// Drop-in safe replacement for unconditional `removeLast()`, which
    /// traps on an empty collection.
    @discardableResult
    mutating func removeLastSafely() -> Element? {
        isEmpty ? nil : removeLast()
    }
}
