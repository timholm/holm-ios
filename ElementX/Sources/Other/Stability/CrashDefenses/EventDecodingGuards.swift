//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Graceful decoding for untrusted payloads.
///
/// Matrix events, push payloads and imported data are attacker-influenced.
/// Decoding them must degrade to `nil`/fallbacks, never trap. Prefer these
/// helpers (or `try?` + `guard`) over `try!`, `as!` and force-unwraps on any
/// value that crossed the network.
///
/// Force-unwrap / force-cast / force-try audit (2026-09-30, whole
/// `ElementX/Sources` + `NSE/Sources`, fixtures/mocks/tests excluded):
///
/// Already safe or deliberately fatal (no change):
/// - `Other/MatrixEntityRegex.swift:38-44` — `try!` on static regexes compiled
///   from hardcoded patterns. A bad pattern fails at first access during
///   development, never from user data.
/// - `Application/AppCoordinator.swift` (`fatalError`, 10 sites) and
///   `Application/Navigation/*` (`fatalError`, 12 sites) — programmer-error
///   assertions for impossible state-machine transitions, not data paths.
/// - IUO outlets and injected services (`Application.swift:69`,
///   `Windowing/WindowManager.swift:17-22`, `Services/Timeline/TimelineProxy.swift:28`,
///   `Services/Media/Provider/MediaSourceProxy.swift:19`,
///   `Screens/Timeline/View/TimelineItemViews/*:12-13` environment values) —
///   set during construction; a missing value is a programming error, not
///   malformed data. `MediaSourceProxy.url` (`URL!`) deserves a future
///   migration to `URL?`, but that ripples through `Hashable` and every media
///   view, so it is documented here rather than changed blindly.
///
/// Fixed alongside this file (surgical, in unowned files):
/// - `NSE/Sources/NotificationContentBuilder.swift:323` — `mutableCopy()
///   as! UNMutableNotificationContent` in the communication-notification path;
///   now a conditional cast that skips the update when the cast fails.
nonisolated enum EventDecodingGuards {
    /// Decodes `data` into `type`, returning `nil` instead of throwing.
    ///
    /// For payloads that crossed the network. Logs nothing: callers decide
    /// whether a failure is worth reporting (most malformed events are not).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
    
    /// Decodes a UTF-8 JSON string into `type`, returning `nil` on any failure.
    static func decode<T: Decodable>(_ type: T.Type, from jsonString: String) -> T? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return decode(type, from: data)
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Decodes `key`, falling back to `defaultValue` when the key is missing,
    /// null or holds an incompatible value.
    ///
    /// Use for fields where the sender's idea of the type may not match ours
    /// (e.g. a boolean arriving as `0`/`1`, or an object arriving as a string).
    func decodeSafely<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }
    
    /// Decodes an optional field, returning `nil` when the key is missing,
    /// null or holds an incompatible value instead of throwing.
    func decodeSafelyIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
