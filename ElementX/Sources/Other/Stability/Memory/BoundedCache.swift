//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// An `NSCache` wrapper with explicit bounds and memory-pressure integration.
///
/// `NSCache` evicts on its own under memory pressure, but without explicit limits
/// its steady-state size is unpredictable. `BoundedCache` requires a count limit and
/// a total cost limit up front, logs evictions so unbounded growth is visible in
/// diagnostics, and registers itself with ``MemoryPressureResponder`` so a memory
/// warning purges it eagerly instead of waiting for the next eviction pass.
///
/// All methods are thread safe (`NSCache` is thread safe; registration uses the
/// responder's internal locking).
final class BoundedCache<Key: AnyObject, Value: AnyObject>: NSObject, MemoryTrimmable {
    private let cache = NSCache<Key, Value>()
    private let name: String
    private let trimActionID: String?
    
    /// Creates a bounded cache.
    ///
    /// - Parameters:
    ///   - name: Diagnostic name, used in eviction logs and as the `NSCache` name.
    ///   - countLimit: Maximum number of objects. 0 means no limit (discouraged).
    ///   - totalCostLimit: Maximum total cost of objects. 0 means no limit (discouraged).
    ///   - purgeOnMemoryWarning: When true (the default), registers a trim action with
    ///     ``MemoryPressureResponder`` that clears the cache on a memory warning.
    init(name: String, countLimit: Int, totalCostLimit: Int, purgeOnMemoryWarning: Bool = true) {
        self.name = name
        super.init()
        cache.name = name
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        cache.delegate = self
        
        if purgeOnMemoryWarning {
            let trimActionID = "bounded-cache-\(name)"
            self.trimActionID = trimActionID
            MemoryPressureResponder.shared.register(self, id: trimActionID)
        } else {
            trimActionID = nil
        }
    }
    
    deinit {
        if let trimActionID {
            MemoryPressureResponder.shared.unregisterTrimAction(id: trimActionID)
        }
    }
    
    /// Returns the object associated with `key`, if present.
    func object(forKey key: Key) -> Value? {
        cache.object(forKey: key)
    }
    
    /// Stores `object` under `key` with an optional cost (defaults to 0).
    ///
    /// Pass a meaningful cost (e.g. byte size) so `totalCostLimit` actually bounds
    /// memory; a cost of 0 leaves the count limit as the only bound.
    func setObject(_ object: Value, forKey key: Key, cost: Int = 0) {
        cache.setObject(object, forKey: key, cost: cost)
    }
    
    /// Removes the object associated with `key`, if present.
    func removeObject(forKey key: Key) {
        cache.removeObject(forKey: key)
    }
    
    /// Removes all objects from the cache.
    func removeAllObjects() {
        cache.removeAllObjects()
    }
    
    // MARK: - MemoryTrimmable
    
    func trimMemory() {
        removeAllObjects()
    }
}

// MARK: - NSCacheDelegate

extension BoundedCache: NSCacheDelegate {
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        MXLog.info("BoundedCache '\(name)' evicted an object (limits or memory pressure).")
    }
}
