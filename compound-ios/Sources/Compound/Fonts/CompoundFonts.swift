//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

public extension Font {
    /// The fonts used by Element as defined in Compound Design Tokens.
    static let compound = CompoundFonts()
}

/// A manual mapping of the Compound font styles to iOS styles. This will be
/// generated directly from the style dictionary in the future.
public struct CompoundFonts {
    // Holm's type system: a serif display face (New York) carries every title and
    // heading, paired with the system sans for body and UI copy. Deliberately
    // unlike Compound's all-sans default.
    private static func serif(_ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    public let bodyXS = Font.caption
    public let bodyXSSemibold = Font.caption.weight(.semibold)
    public let bodySM = Font.footnote
    public let bodySMSemibold = Font.footnote.weight(.semibold)
    public let bodyMD = Font.subheadline
    public let bodyMDSemibold = Font.subheadline.weight(.semibold)
    public let bodyLG = Font.body
    public let bodyLGSemibold = Font.body.weight(.semibold)
    public let headingSM = Font.title3
    public let headingSMSemibold = Font.title3.weight(.semibold)
    public let headingMD = Font.title2
    public let headingMDBold = Font.title2.bold()
    public let headingLG = Font.title.weight(.light)
    public let headingLGBold = Font.title.weight(.semibold)
    public let headingXL = Font.largeTitle.weight(.light)
    public let headingXLBold = Font.largeTitle.weight(.semibold)
}

public extension Font.TextStyle {
    /// The text styles used by Element as defined in Compound Design Tokens.
    static let compound = CompoundTextStyles()
}

/// A manual mapping of the Compound font styles to iOS text styles. This is useful
/// for `@ScaledMetric` along with modifiers such as `scaledPadding` etc.
public struct CompoundTextStyles {
    public let bodyXS = Font.TextStyle.caption
    public let bodySM = Font.TextStyle.footnote
    public let bodyMD = Font.TextStyle.subheadline
    public let bodyLG = Font.TextStyle.body
    public let headingSM = Font.TextStyle.title3
    public let headingMD = Font.TextStyle.title2
    public let headingLG = Font.TextStyle.title
    public let headingXL = Font.TextStyle.largeTitle
}
