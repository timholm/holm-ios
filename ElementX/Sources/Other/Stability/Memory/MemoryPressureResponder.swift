//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import UIKit

/// A type that can shed in-memory state when the system is under memory pressure.
///
/// Conform caches to this protocol and register them with ``MemoryPressureResponder``
/// so their contents are trimmed on `UIApplication.didReceiveMemoryWarningNotification`
/// instead of growing until the OS jetsams the app.
protocol MemoryTrimmable: AnyObject {
    /// Drop as much in-memory state as is safe; the data must be recoverable
    /// (re-downloadable, re-computable, or re-readable from disk).
    func trimMemory()
}

/// Central coordinator for memory-pressure responses.
///
/// Caches register trim actions (or conform to ``MemoryTrimmable`` and register
/// themselves); when the system posts a memory warning every registered action runs
/// on the main thread. Registration is idempotent per identifier, so configuring a
/// cache more than once (e.g. once per login) replaces rather than duplicates its
/// trim action.
///
/// Thread safe: registrations may happen from any thread. Trim actions run outside
/// the internal lock so they may safely register or unregister other actions.
final class MemoryPressureResponder {
    static let shared = MemoryPressureResponder()
    
    private let lock = NSLock()
    private var trimActions = [String: () -> Void]()
    private var observation: AnyCancellable?
    
    private init() {
        observation = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
    }
    
    /// Registers a trim action, replacing any previous action with the same identifier.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for the action (e.g. `"kingfisher-image-memory-cache"`).
    ///     Re-registering with the same id replaces the previous action.
    ///   - action: The work to perform on a memory warning. Must be quick and must not
    ///     allocate significant memory itself.
    func registerTrimAction(id: String, action: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        trimActions[id] = action
    }
    
    /// Registers a trimmable cache. Equivalent to registering its `trimMemory` method.
    ///
    /// The cache is held weakly: the trim action becomes a no-op when the cache
    /// deallocates, so manual unregistration is optional (but still recommended).
    func register(_ trimmable: MemoryTrimmable, id: String) {
        registerTrimAction(id: id) { [weak trimmable] in
            trimmable?.trimMemory()
        }
    }
    
    /// Removes the trim action registered under `id`, if any.
    func unregisterTrimAction(id: String) {
        lock.lock()
        defer { lock.unlock() }
        trimActions.removeValue(forKey: id)
    }
    
    // MARK: - Private
    
    private func handleMemoryWarning() {
        lock.lock()
        let actions = Array(trimActions.values)
        lock.unlock()
        
        MXLog.warning("Received memory warning, running \(actions.count) registered trim actions.")
        for action in actions {
            action()
        }
    }
}
