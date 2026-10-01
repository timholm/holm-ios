//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Synchronization

/// Lightweight last-known-state recorder for crash diagnosis.
///
/// Watchdog kills and other hard crashes leave no stack trace, which is
/// exactly what telemetry reported (`app.crashed_previous_session` with no
/// trace, last screen `chats`). Breadcrumbs fix that: the app continuously
/// records tiny "screen X / action Y" markers to disk, and the *next* launch
/// reads them back so the crash report can say what the dead session was
/// doing.
///
/// Design constraints (all honoured):
/// - Tiny: an in-memory ring buffer (128 entries max) plus one small log file.
/// - Synchronous-safe: callable from any thread, including app-delegate
///   launch paths. State is guarded by `Mutex`; the critical section only
///   appends to an array. Disk writes are throttled (at most every
///   `persistInterval` seconds, or every `persistEntryThreshold` entries).
/// - Never itself crashes: every filesystem operation uses `try?`, every
///   optional is handled, there are no force-unwraps and no `fatalError`.
/// - No PII: record screens and action names only — never message bodies,
///   user IDs or media URLs.
///
/// Lifecycle:
/// 1. During the run, call `record(screen:)` / `record(action:)` at interesting
///    points (screen appearances, pagination, uploads).
/// 2. At launch, call `previousSessionBreadcrumbs()` once, attach the result
///    to the telemetry session or bug report, then keep recording. Entries
///    left over from the previous run are precisely the ones that matter:
///    a cleanly-terminated session would have been superseded by the new
///    launch's own markers.
///
/// `nonisolated` (like `TrackedUserDefaults`): every method is synchronously
/// callable from any thread; internal state is guarded by `Mutex`.
final nonisolated class CrashBreadcrumbs: Sendable {
    /// The app-wide recorder. Prefer this over creating instances.
    static let shared = CrashBreadcrumbs()
    
    /// Maximum markers kept in memory and on disk. Oldest are dropped first.
    private static let maximumEntries = 128
    /// Minimum seconds between disk writes; bounds the I/O cost of `record`.
    private static let persistInterval: TimeInterval = 30
    /// Entries that force a disk write even before `persistInterval` elapses.
    private static let persistEntryThreshold = 16
    
    private struct State {
        var entries: [String] = []
        var unpersistedCount = 0
        var lastPersisted = Date.distantPast
    }
    
    private let state = Mutex(State())
    private let fileURL: URL
    
    /// Creates a recorder. `fileURL` is for tests; production uses `shared`,
    /// which writes to the caches directory (never backed up, survives crashes).
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            // "/dev/null" fallback: every write becomes a `try?` no-op rather
            // than a crash if the caches directory is ever unreachable.
            self.fileURL = cachesDirectory?.appendingPathComponent("holm-crash-breadcrumbs.log", isDirectory: false)
                ?? URL(fileURLWithPath: "/dev/null")
        }
    }
    
    /// Records a free-form marker, e.g. `"timeline.paginate.back"`.
    func record(_ message: String) {
        let entry = "\(Self.timestamp()): \(message)"
        let shouldPersist = state.withLock { state -> Bool in
            state.entries.append(entry)
            if state.entries.count > Self.maximumEntries {
                state.entries.removeFirst(state.entries.count - Self.maximumEntries)
            }
            state.unpersistedCount += 1
            let due = state.unpersistedCount >= Self.persistEntryThreshold
                || Date().timeIntervalSince(state.lastPersisted) >= Self.persistInterval
            if due {
                state.unpersistedCount = 0
                state.lastPersisted = Date()
            }
            return due
        }
        if shouldPersist {
            persist()
        }
    }
    
    /// Records the currently visible screen, e.g. `"chats"`, `"room"`.
    func record(screen: String) {
        record("screen:\(screen)")
    }
    
    /// Records a user- or system-initiated action, e.g. `"send_message"`.
    func record(action: String) {
        record("action:\(action)")
    }
    
    /// Returns the markers persisted by the previous session, then clears them.
    ///
    /// Call exactly once at launch, before recording new markers, and attach
    /// the result to the telemetry session or bug report. An empty array means
    /// either a first launch or nothing was recorded — both are normal.
    func previousSessionBreadcrumbs() -> [String] {
        let contents = try? String(contentsOf: fileURL, encoding: .utf8)
        // Clear regardless of read success so a corrupt file can't pile up.
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        state.withLock { state in
            state.entries.removeAll()
            state.unpersistedCount = 0
        }
        guard let contents, !contents.isEmpty else {
            return []
        }
        return contents.split(separator: "\n").map(String.init)
    }
    
    /// Forces the in-memory markers to disk. Safe to call rarely (e.g. on
    /// backgrounding); `record` already persists on a throttle.
    func flush() {
        persist()
    }
    
    // MARK: - Private
    
    private func persist() {
        let entries = state.withLock { $0.entries }
        guard !entries.isEmpty else {
            return
        }
        try? entries.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private static func timestamp() -> String {
        // Created per call: persists are throttled and records are cheap
        // strings, so no shared formatter (and its thread-safety) is needed.
        ISO8601DateFormatter().string(from: Date())
    }
}
