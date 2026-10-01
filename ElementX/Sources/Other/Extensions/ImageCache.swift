//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Kingfisher

nonisolated extension ImageCache {
    static var onlyInMemory: ImageCache {
        let result = ImageCache.default
        // Bound the in-memory image cache: without explicit limits decoded images
        // accumulate until the OS jetsams the app. NSCache still evicts under
        // pressure on its own, but explicit limits keep steady-state memory
        // predictable (track: ios-stability-memory).
        result.memoryStorage.config.countLimit = 300
        result.memoryStorage.config.totalCostLimit = 150 * 1024 * 1024
        result.memoryStorage.config.keepWhenEnteringBackground = true
        result.diskStorage.config.sizeLimit = 1
        
        // Purge decoded images on memory warning instead of waiting for jetsam.
        // Registered by id so repeated evaluations (one per session setup) replace
        // rather than duplicate the trim action.
        MemoryPressureResponder.shared.registerTrimAction(id: "kingfisher-image-memory-cache") { [weak result] in
            result?.clearMemoryCache()
        }
        
        return result
    }
    
    static var onlyOnDisk: ImageCache {
        let result = ImageCache.default
        result.memoryStorage.config.totalCostLimit = 1
        return result
    }
}
