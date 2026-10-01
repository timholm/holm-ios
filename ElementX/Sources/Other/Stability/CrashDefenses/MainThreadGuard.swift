//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// DEBUG-only watchdog protection for main-thread stalls.
///
/// Telemetry showed `main.stall` events and an `app.crashed_previous_session`
/// with no stack trace on the chats screen — the signature of a watchdog
/// kill. Watchdog kills leave no trace in-process, so the defence is
/// twofold: keep heavy work off the main thread, and record breadcrumbs
/// (see `CrashBreadcrumbs`) so the next launch can report what the crashed
/// session was doing.
///
/// This helper asserts in DEBUG builds when synchronous heavy work runs on
/// the main thread. It compiles to nothing in release, so it can never
/// introduce a production crash — it is a development aid, not a runtime
/// guard.
///
/// Known main-thread heavy call sites (2026-09-30 audit). These were NOT
/// moved here — hopping threads is behavioural and needs Mac verification.
/// Each should wrap its synchronous work in `Task.detached` (or be made
/// `nonisolated`) so the main actor stays responsive:
/// - `Services/Client/ClientProxy.swift:637` (`uploadMedia`) —
///   `Data(contentsOf:)` reads the entire media file synchronously.
///   `ClientProxy` is a plain class, so under the target's
///   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this runs on the main thread.
/// - `Services/Client/ClientProxy.swift:743` (`setUserAvatar`) — same
///   pattern, `Data(contentsOf:)` on the main thread.
/// - `Services/Room/JoinedRoomProxy.swift:409` (`uploadAvatar`) — same
///   pattern, `Data(contentsOf:)` on the main thread.
/// - `Services/Media/MediaUploadingPreprocessor.swift:305`
///   (`stripLocationFromImage`) — `NSData(contentsOf:)` plus
///   `CGImageSourceCreateWithData` image decode; the struct is a plain
///   `struct`, hence main-actor isolated by default.
/// - `Services/Authentication/ClassicApp/ClassicAppAccountManager.swift:35,93`
///   — `Data(contentsOf:)` during classic-app import (one-shot, low risk).
///
/// Suggested integration: call `MainThreadGuard.assertNotOnMainThread()` at
/// the top of any function that does file I/O, image decoding or JSON
/// parsing, then verify with a DEBUG run that no assertion fires during
/// normal use.
nonisolated enum MainThreadGuard {
    /// Asserts (DEBUG only) that the current thread is not the main thread.
    ///
    /// Place at the top of synchronous heavy work: file I/O, image decode,
    /// JSON parsing, regex over large bodies. In release builds this is a
    /// no-op — it documents intent and catches regressions during
    /// development without risking production.
    static func assertNotOnMainThread(_ message: @autoclosure () -> String = "Synchronous heavy work is running on the main thread; move it off to avoid watchdog stalls.",
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        #if DEBUG
        assert(!Thread.isMainThread, message(), file: file, line: line)
        #endif
        // Release builds: intentionally a no-op. Never crash production for a
        // performance observation.
    }
    
    /// Returns `true` when called on the main thread.
    ///
    /// For call sites that cannot assert (e.g. code that legitimately runs on
    /// either thread) but want to choose a cheaper path off the main thread.
    static var isMainThread: Bool {
        Thread.isMainThread
    }
}
