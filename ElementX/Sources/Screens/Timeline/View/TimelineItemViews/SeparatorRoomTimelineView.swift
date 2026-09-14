//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct SeparatorRoomTimelineView: View {
    let timelineItem: SeparatorRoomTimelineItem
    
    /// A date reads as an editorial rule with the day set into it, rather than
    /// a bold word floating in the middle of the conversation.
    var body: some View {
        HStack(spacing: 12) {
            line
            Text(timelineItem.timestamp.formattedDateSeparator())
                .font(.compound.bodyXS)
                .foregroundColor(.compound.textSecondary)
                .fixedSize()
            line
        }
        .padding(.horizontal, 24.0)
        .padding(.vertical, 14.0)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.compound.borderInteractiveSecondary)
            .frame(height: 1 / UIScreen.main.scale)
            .frame(maxWidth: .infinity)
    }
}

struct SeparatorRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        let item = SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("Separator")),
                                             timestamp: .mock)
        SeparatorRoomTimelineView(timelineItem: item)
    }
}
