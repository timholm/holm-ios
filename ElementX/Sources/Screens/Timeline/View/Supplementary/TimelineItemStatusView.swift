//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct TimelineItemStatusView: View {
    let timelineItem: EventBasedTimelineItemProtocol
    let adjustedDeliveryStatus: TimelineItemDeliveryStatus?
    @EnvironmentObject private var context: TimelineViewModel.Context
    
    private var isLastOutgoingMessage: Bool {
        // Read the last key directly: materialising `uniqueIDs` copies the whole
        // dictionary's keys on every evaluation of every status view.
        timelineItem.isOutgoing && context.viewState.timelineState.itemsDictionary.keys.last == timelineItem.id.uniqueID
    }
    
    var body: some View {
        mainContent
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if context.viewState.timelineKind == .pinned {
            // Do not display any status when is a pinned events timeline
            EmptyView()
        } else if context.viewState.showReadReceipts, !timelineItem.properties.orderedReadReceipts.isEmpty {
            readReceipts
        } else {
            deliveryStatusBadge
        }
    }
    
    @ViewBuilder
    var deliveryStatusBadge: some View {
        switch adjustedDeliveryStatus {
        case .sending:
            TimelineDeliveryStatusView(deliveryStatus: .sending)
        case .sent, .none:
            if isLastOutgoingMessage {
                // We only display the sent icon for the latest outgoing message
                TimelineDeliveryStatusView(deliveryStatus: .sent)
            }
        case .sendingFailed:
            // Bubbles handle the case internally
            EmptyView()
        }
    }
    
    var readReceipts: some View {
        TimelineReadReceiptsView(timelineItem: timelineItem)
            .environmentObject(context)
    }
}
