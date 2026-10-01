//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Memoizes the flattened message preview shown in reply and thread summary rows.
///
/// `TimelineViewState.buildMessagePreview` converts the formatted body into an
/// `NSMutableAttributedString` and walks every run resolving pills, so calling it
/// from `body` repeats that work on every view update. This box caches the result
/// per view instance and only rebuilds when the inputs change. Member display names
/// feed the preview, so their fingerprint is part of the cache key and member
/// updates invalidate the entry.
final class MessagePreviewCache {
    private var formattedBody: AttributedString?
    private var plainBody: String?
    private var membersFingerprint: Int?
    private var cachedPreview = ""
    
    /// Returns the cached preview, rebuilding it when the inputs changed since the last call.
    func preview(for viewState: TimelineViewState, formattedBody: AttributedString?, plainBody: String) -> String {
        let fingerprint = Self.membersFingerprint(viewState.members)
        
        if self.formattedBody == formattedBody,
           self.plainBody == plainBody,
           self.membersFingerprint == fingerprint {
            return cachedPreview
        }
        
        let preview = viewState.buildMessagePreview(formattedBody: formattedBody, plainBody: plainBody)
        
        self.formattedBody = formattedBody
        self.plainBody = plainBody
        self.membersFingerprint = fingerprint
        cachedPreview = preview
        
        return preview
    }
    
    /// `buildMessagePreview` only reads display names from members, so only they contribute to the fingerprint.
    private static func membersFingerprint(_ members: [String: RoomMemberState]) -> Int {
        members.reduce(0) { fingerprint, member in
            fingerprint ^ member.key.hashValue ^ (member.value.displayName?.hashValue ?? 0)
        }
    }
}
