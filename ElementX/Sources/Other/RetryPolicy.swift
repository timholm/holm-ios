//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Computes delays for retrying failed operations.
enum RetryPolicy {
    /// The delay before the given 1-based attempt: `baseDelay` doubling with every attempt,
    /// capped at `maxDelay`, plus up to `maxJitter` of additional random delay so concurrent
    /// retries don't stampede in lockstep.
    static func delayBeforeRetry(attempt: Int,
                                 baseDelay: Duration = .milliseconds(250),
                                 maxDelay: Duration = .seconds(30),
                                 maxJitter: Duration = .milliseconds(250)) -> Duration {
        let exponential = min(seconds(maxDelay), seconds(baseDelay) * pow(2, Double(max(0, attempt - 1))))
        let jittered = exponential + Double.random(in: 0...seconds(maxJitter))
        return .milliseconds(Int64(jittered * 1000))
    }
    
    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
