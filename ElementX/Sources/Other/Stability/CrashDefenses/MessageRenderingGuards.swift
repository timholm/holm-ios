//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Guards that keep malformed message content from crashing rendering.
///
/// Message content arrives from the network and must be treated as hostile:
/// empty bodies, zero-size media, malformed URLs and blank blurhashes all
/// occur in the wild. These helpers centralise the "render a fallback instead
/// of crashing" policy so views stay declarative.
///
/// Audit of message rendering (2026-09-30) — already nil-safe, no changes needed:
/// - `Screens/Timeline/View/TimelineItemViews/ImageRoomTimelineView.swift`
///   uses optional chaining + `??` fallbacks for caption, thumbnail and media
///   provider throughout; `ContentScanningView` handles the scanning states.
/// - `Screens/Timeline/View/TimelineItemViews/LocationRoomTimelineView.swift:30`
///   and `LiveLocationRoomTimelineView.swift` render the map only `if let`
///   the geo URI parses, falling back to `FormattedBodyText` otherwise.
/// - `Screens/Timeline/View/TimelineItemViews/PollRoomTimelineView.swift:34-41`
///   guards `let eventID` before sending any poll action.
/// - `Other/SwiftUI/Layout/TimelineMediaFrame.swift` falls back to a fixed
///   100x100 frame when `imageInfo` or its aspect ratio is missing.
/// - `Services/Timeline/TimelineItemProxy.swift:364-371` (`MediaInfoProxy`)
///   only computes an aspect ratio when `width > 0, height > 0` — no
///   division by zero.
/// - `Other/BlurHashDecode.swift:29-55` validates the blurhash length and
///   guards every Core Foundation allocation.
///
/// Fixed alongside this file (surgical, in unowned files):
/// - `Other/BlurHashEncode.swift:69` — `factors.first!` trapped when the
///   factor loop produced nothing; now returns `nil`.
/// - `Other/BlurHashEncode.swift:37-38` — `CGContext(...)!` trapped on
///   zero-size images; now guarded before context creation.
nonisolated enum MessageRenderingGuards {
    /// Returns `string` when it holds non-whitespace content, otherwise `nil`.
    ///
    /// Malformed events sometimes carry empty or blank bodies. Rendering
    /// nothing beats rendering a broken bubble.
    static func nonBlank(_ string: String?) -> String? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
    }
    
    /// Builds a URL from an event-provided string.
    ///
    /// Returns `nil` for missing, blank or malformed strings. Never traps:
    /// `URL(string:)` itself is failable, this just funnels the common
    /// pre-checks through one place.
    static func url(from string: String?) -> URL? {
        guard let string = nonBlank(string) else {
            return nil
        }
        return URL(string: string)
    }
    
    /// Whether a media `size` taken from an event can actually be laid out.
    ///
    /// Zero, negative or non-finite dimensions must fall back to a default
    /// frame — aspect-ratio math on them produces NaN or infinite layouts,
    /// which SwiftUI resolves by collapsing or, worse, looping layout.
    static func isRenderable(_ size: CGSize?) -> Bool {
        guard let size else {
            return false
        }
        return size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite
    }
    
    /// Clamps an event-provided aspect ratio into a sane layout range.
    ///
    /// Returns `nil` when the input is missing, non-positive or non-finite so
    /// callers can fall back to their default frame (see `isRenderable`).
    static func clampedAspectRatio(_ aspectRatio: CGFloat?, min minRatio: CGFloat = 0.1, max maxRatio: CGFloat = 10) -> CGFloat? {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else {
            return nil
        }
        return Swift.min(Swift.max(aspectRatio, minRatio), maxRatio)
    }
    
    /// Returns the blurhash when it can actually be decoded, otherwise `nil`.
    ///
    /// `BlurHashDecode` already validates length, but an empty string should
    /// never reach the decoder — treat it as "no placeholder".
    static func validBlurhash(_ blurhash: String?) -> String? {
        nonBlank(blurhash)
    }
}
