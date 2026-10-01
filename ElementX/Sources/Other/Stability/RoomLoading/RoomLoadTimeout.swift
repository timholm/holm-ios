//
// Copyright 2026 Element Creations Ltd.
// Copyright 2026 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Time budgets for the background phases of room loading.
///
/// When a phase exceeds its budget the room proceeds with degraded UI
/// (placeholders) instead of waiting: first paint must never depend on these.
enum RoomLoadBudgets {
    /// Max time to wait for the DM verification-badge identity lookup
    /// (cross-signing / key resolution) before showing the unverified placeholder.
    static let cryptoWarmup: TimeInterval = 3
    /// Max time to wait for the pinned-events timeline before leaving the pins
    /// banner in its loading state.
    static let pinnedBanner: TimeInterval = 5
}

/// Runs `operation` with a deadline. Returns the operation's value, or `nil`
/// if the deadline fires first.
///
/// The loser of the race is cancelled; note the underlying task still runs to
/// its next cancellation point, so callers must already have proceeded with
/// degraded UI — this only bounds how long the background work is awaited.
enum RoomLoadTimeout {
    /// - Parameters:
    ///   - seconds: Deadline for `operation`.
    ///   - operation: The work to bound. Must be `@Sendable`; capture values,
    ///     not `self`, where practical.
    /// - Returns: The operation's result, or `nil` on timeout.
    static func withTimeout<T: Sendable>(seconds: TimeInterval,
                                         operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self, returning: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            // The first child to finish wins; the other is cancelled.
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }
    }
}
