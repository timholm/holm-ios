//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

extension View {
    /// - Parameters:
    ///   - isOutgoing: rounds the corners according to the side it shows on, defaults to true
    ///   - insets: defaults to the comfortable padding used for text bubbles
    ///   - color: self explanatory, defaults to subtle secondary
    ///   - borderColor: an optional colour for a border around the bubble
    func bubbleBackground(isOutgoing: Bool = true,
                          insets: EdgeInsets = .init(top: 10, leading: 14, bottom: 10, trailing: 14),
                          color: @autoclosure @MainActor () -> Color? = .compound.bgSubtleSecondary,
                          borderColor: @autoclosure @MainActor () -> Color? = nil) -> some View {
        modifier(TimelineItemBubbleBackgroundModifier(isOutgoing: isOutgoing,
                                                      insets: insets,
                                                      color: color(),
                                                      borderColor: borderColor()))
    }
}

private struct TimelineItemBubbleBackgroundModifier: ViewModifier {
    @Environment(\.timelineGroupStyle) private var timelineGroupStyle
    
    let isOutgoing: Bool
    let insets: EdgeInsets
    var color: Color?
    var borderColor: Color?
    
    /// Soft, modern bubble corners, larger than Compound's default for a friendlier chat feel.
    private let bubbleCornerRadius: CGFloat = 18
    
    func body(content: Content) -> some View {
        content
            .padding(insets)
            .background(color)
            .cornerRadius(bubbleCornerRadius, corners: roundedCorners)
            .overlay {
                if let borderColor {
                    RoundedCornerShape(radius: bubbleCornerRadius, corners: roundedCorners)
                        .stroke(borderColor)
                }
            }
    }
    
    private var roundedCorners: UIRectCorner {
        switch timelineGroupStyle {
        case .single:
            return .allCorners
        case .first:
            if isOutgoing {
                return [.topLeft, .topRight, .bottomLeft]
            } else {
                return [.topLeft, .topRight, .bottomRight]
            }
        case .middle:
            return isOutgoing ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight]
        case .last:
            if isOutgoing {
                return [.topLeft, .bottomLeft, .bottomRight]
            } else {
                return [.topRight, .bottomLeft, .bottomRight]
            }
        }
    }
}
