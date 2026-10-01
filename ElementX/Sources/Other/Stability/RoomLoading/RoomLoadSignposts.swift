//
// Copyright 2026 Element Creations Ltd.
// Copyright 2026 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import os

/// `os_signpost` instrumentation for the room-open critical path.
///
/// Subsystem/category are fixed so a single Instruments trace shows the whole
/// story: open a room on the Mac with the "Logging" instrument recording and
/// filter the signpost track by subsystem `com.holm.roomload`.
///
/// The 14.6s `room.first_render` seen in telemetry had no main-thread stall in
/// the window, so the render gate is unknown. These signposts exist to make it
/// visible rather than to assert where it is: every phase of room load gets an
/// interval, first paint gets an instant event.
///
/// ## Expected sequence (healthy room open)
/// 1. `room_open` begins (RoomScreenCoordinator.init)
/// 2. `coordinator_setup` begins/ends (all three view models are built here,
///    including the timeline view model — see the Worker 1/2 notes below)
/// 3. `room_viewmodel_init` begins/ends (cached RoomInfo -> header state)
/// 4. `first_paint` event (RoomScreen.onAppear — SwiftUI rendered the room)
/// 5. `room_open` ends
/// 6. `crypto_warmup` begins/ends (verification badge identity lookup, background)
/// 7. `pinned_banner` begins/ends (pinned-events timeline, background)
///
/// ## Integration points for the other stability workers
/// Room loading spans three areas; only the RoomScreen parts are instrumented
/// here. The matching one-liners for the other workers:
///
/// Worker 1 (`Screens/Timeline/`):
/// - Around `TimelineViewModel.init`'s `buildTimelineViews(timelineItems:)`:
///   `let id = RoomLoadSignposts.begin(.timelineBuild)` / `RoomLoadSignposts.end(.timelineBuild, id: id)`
/// - Around `focusOnEvent` / `paginateBackwards` / `paginateForwards` gap fills:
///   `RoomLoadSignposts.begin(.gapFill)` / `end`
///
/// Worker 2 (`Services/`):
/// - Around `TimelineController.init`'s `configureActiveTimelineItemProvider()`:
///   `RoomLoadSignposts.begin(.timelineAttach)` / `end`
/// - If `JoinedRoomProxy.timeline` (the Rust timeline handle) is ever created
///   lazily, wrap that creation in `.timelineAttach` too — it is currently the
///   biggest unknown on the attach path.
enum RoomLoadSignposts {
    static let subsystem = "com.holm.roomload"
    static let category = "RoomLoad"
    
    private static let log = OSLog(subsystem: subsystem, category: category)
    
    /// A timed phase of room loading. Raw values are the names shown in
    /// Instruments; keep them stable so traces stay comparable.
    enum Phase: String {
        /// Whole flow: RoomScreenCoordinator.init -> first paint.
        case roomOpen = "room_open"
        /// Synchronous view-model construction inside the coordinator init.
        /// Includes the timeline view model build (Worker 1 area).
        case coordinatorSetup = "coordinator_setup"
        /// RoomScreenViewModel init: cached RoomInfo -> header state.
        case viewModelInit = "room_viewmodel_init"
        /// Worker 2 integration: TimelineController init + item-provider subscribe.
        case timelineAttach = "timeline_attach"
        /// Worker 1 integration: TimelineViewModel.buildTimelineViews.
        case timelineBuild = "timeline_build"
        /// Background identity/verification lookup for the DM badge.
        case cryptoWarmup = "crypto_warmup"
        /// Background pinned-events timeline creation for the pins banner.
        case pinnedBanner = "pinned_banner"
        /// Worker 1 integration: post-first-paint gap fills (pagination, focus).
        case gapFill = "gap_fill"
    }
    
    /// An instantaneous marker.
    enum Event: String {
        /// SwiftUI rendered the room screen for the first time.
        case firstPaint = "first_paint"
        /// cryptoWarmup exceeded its budget; degraded placeholder is shown.
        case cryptoWarmupTimeout = "crypto_warmup_timeout"
        /// pinnedBanner exceeded its budget; banner stays in loading state.
        case pinnedBannerTimeout = "pinned_banner_timeout"
        /// retryDecryption was kicked off (app became active).
        case retryDecryption = "retry_decryption"
    }
    
    /// Begins a signpost interval for `phase`. Pair with `end(_:id:)`.
    @discardableResult
    static func begin(_ phase: Phase) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: phase.signpostName, signpostID: id)
        return id
    }
    
    /// Ends the interval started by `begin(_:)` with the same id.
    static func end(_ phase: Phase, id: OSSignpostID) {
        os_signpost(.end, log: log, name: phase.signpostName, signpostID: id)
    }
    
    /// Emits an instantaneous signpost event.
    static func event(_ event: Event, message: String? = nil) {
        if let message, !message.isEmpty {
            os_signpost(.event, log: log, name: event.signpostName, "%{public}s", message)
        } else {
            os_signpost(.event, log: log, name: event.signpostName)
        }
    }
}

private extension RoomLoadSignposts.Phase {
    var signpostName: StaticString {
        switch self {
        case .roomOpen: return "room_open"
        case .coordinatorSetup: return "coordinator_setup"
        case .viewModelInit: return "room_viewmodel_init"
        case .timelineAttach: return "timeline_attach"
        case .timelineBuild: return "timeline_build"
        case .cryptoWarmup: return "crypto_warmup"
        case .pinnedBanner: return "pinned_banner"
        case .gapFill: return "gap_fill"
        }
    }
}

private extension RoomLoadSignposts.Event {
    var signpostName: StaticString {
        switch self {
        case .firstPaint: return "first_paint"
        case .cryptoWarmupTimeout: return "crypto_warmup_timeout"
        case .pinnedBannerTimeout: return "pinned_banner_timeout"
        case .retryDecryption: return "retry_decryption"
        }
    }
}
